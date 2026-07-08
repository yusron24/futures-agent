const coingecko = require('./coingeckoService');
const { getTopCoins } = coingecko;
const { calculateRSI, toDailySeries } = require('./indicators');
const { getSettings } = require('../db/settingsStore');
const { getLatestScreening } = require('./screeningService');

// Coins per tick and pace between ticks. Deliberately independent from
// (and paused during) the main screening cycle's own CoinGecko calls, so
// the two don't compound into more 429s than either would cause alone.
// At 5 coins/20s this pool rotates through ~15 coins/min; a 100-coin pool
// finishes a full sweep roughly every ~7 minutes, 250 coins ~17 minutes.
const BATCH_SIZE = 5;
const TICK_MS = 20000;

let candidatePool = []; // [{ id, symbol, name, image, price, change24h, marketCapRank }]
let cursor = 0;
let rotationsCompleted = 0;
let lastTickAt = null;

// coinId -> { id, symbol, name, image, price, change24h, marketCapRank, rsi, updatedAt }
const rsiCache = new Map();

function toQuickInfo(coin) {
  return {
    id: coin.id,
    symbol: (coin.symbol || '').toUpperCase(),
    name: coin.name,
    image: coin.image,
    price: coin.current_price,
    change24h: coin.price_change_percentage_24h_in_currency ?? coin.price_change_percentage_24h ?? null,
    marketCapRank: coin.market_cap_rank,
  };
}

async function refreshCandidatePool() {
  const { rsiScreenerCoinsLimit } = getSettings();
  const coins = await getTopCoins(rsiScreenerCoinsLimit);
  candidatePool = coins.map(toQuickInfo);
  cursor = 0;
  // Drop cached entries for coins that fell out of the pool (e.g. limit lowered).
  const poolIds = new Set(candidatePool.map((c) => c.id));
  for (const id of rsiCache.keys()) {
    if (!poolIds.has(id)) rsiCache.delete(id);
  }
}

/**
 * Processes the next batch of coins in the rotation, computing RSI(14)
 * from 30 days of daily closes. Skipped entirely while the main
 * screening cycle is running, to avoid the two features fighting over
 * CoinGecko's rate limit at the same time.
 */
async function runBatch() {
  if (getLatestScreening().isRunning) return;

  try {
    if (candidatePool.length === 0 || cursor >= candidatePool.length) {
      await refreshCandidatePool();
      if (candidatePool.length) rotationsCompleted += 1;
    }
    if (!candidatePool.length) return;

    const batch = candidatePool.slice(cursor, cursor + BATCH_SIZE);
    cursor += BATCH_SIZE;

    for (const coin of batch) {
      try {
        const chart = await coingecko.getCoinMarketChart(coin.id, 30);
        const dailyCloses = toDailySeries(chart.prices || []);
        const rsi = calculateRSI(dailyCloses, 14);
        rsiCache.set(coin.id, {
          ...coin,
          rsi: rsi != null ? Math.round(rsi * 100) / 100 : null,
          updatedAt: new Date().toISOString(),
        });
      } catch (err) {
        console.warn(`[rsi-screener] failed for ${coin.id}: ${err.message}`);
        // keep whatever was cached before rather than blanking the coin out
      }
    }
    lastTickAt = new Date().toISOString();
  } catch (err) {
    console.error('[rsi-screener] batch failed:', err.message);
  }
}

function startRsiScreenerLoop() {
  setTimeout(runBatch, 8000); // staggered from the main scheduler's own 3s initial run
  setInterval(runBatch, TICK_MS);
}

/** Coins currently oversold (RSI<30) / overbought (RSI>70) within the scanned pool. */
function getRsiScreenerResults() {
  const scanned = Array.from(rsiCache.values()).filter((c) => c.rsi != null);
  const oversold = scanned.filter((c) => c.rsi < 30).sort((a, b) => a.rsi - b.rsi);
  const overbought = scanned.filter((c) => c.rsi > 70).sort((a, b) => b.rsi - a.rsi);

  return {
    updatedAt: lastTickAt,
    poolSize: candidatePool.length,
    scannedCount: scanned.length,
    rotationsCompleted,
    oversold,
    overbought,
  };
}

module.exports = { startRsiScreenerLoop, runBatch, getRsiScreenerResults };
