const db = require('../db/database');
const binance = require('./binanceService');
const { calculateRSI, calculateMACD, calculateVolatility } = require('./indicators');
const { computeScore } = require('./scoringService');
const { getSocialMomentum, isSocialConfigured } = require('./socialService');
const { getOnchainMetrics } = require('./onchainService');
const { getSettings } = require('../db/settingsStore');

const NEW_LISTING_DAYS = 30;

let latestScreening = { coins: [], updatedAt: null, isRunning: false };
let lastTriggeredAt = 0;
const MIN_MANUAL_REFRESH_GAP_MS = 15000;

function getWatchlistCoinIds() {
  const rows = db.prepare('SELECT coin_id FROM watchlist').all();
  return new Set(rows.map((r) => r.coin_id));
}

function round(n, digits = 2) {
  if (n == null || Number.isNaN(n)) return null;
  const factor = 10 ** digits;
  return Math.round(n * factor) / factor;
}

/**
 * RSI(14)/MACD/volume-ratio/7d-change all come from the same 40-day daily
 * klines fetch - Binance gives OHLCV directly (unlike CoinGecko's
 * separate prices/volumes arrays), so this is a single request per coin.
 */
async function computeKlineMetrics(entry) {
  try {
    const klines = await binance.getDailyKlines(entry.symbol, 40);
    const closes = klines.map((k) => parseFloat(k[4]));
    const quoteVolumes = klines.map((k) => parseFloat(k[7]));

    const rsi = calculateRSI(closes, 14);
    const macd = calculateMACD(closes, 12, 26, 9);

    let volumeRatio = null;
    if (quoteVolumes.length >= 2) {
      const latest = quoteVolumes[quoteVolumes.length - 1];
      const prior = quoteVolumes.slice(0, -1);
      const avgPrior = prior.reduce((a, b) => a + b, 0) / prior.length;
      volumeRatio = avgPrior > 0 ? latest / avgPrior : null;
    }

    let change7d = null;
    if (closes.length >= 8) {
      const weekAgoClose = closes[closes.length - 8];
      change7d = weekAgoClose > 0 ? ((entry.price - weekAgoClose) / weekAgoClose) * 100 : null;
    }

    return { rsi, macdHistogram: macd ? macd.histogram : null, volumeRatio, change7d };
  } catch (err) {
    console.warn(`[screening] klines failed for ${entry.symbol}: ${err.message}`);
    return { rsi: null, macdHistogram: null, volumeRatio: null, change7d: null };
  }
}

async function computeSymbolMetrics(entry) {
  const avgPrice = (entry.high24h + entry.low24h) / 2 || entry.price;
  const volatilityPct = calculateVolatility(entry.high24h, entry.low24h, avgPrice);

  let isNew = false;
  if (entry.onboardDate) {
    const daysSinceOnboard = (Date.now() - entry.onboardDate) / 86400000;
    isNew = daysSinceOnboard <= NEW_LISTING_DAYS;
  }

  const kline = await computeKlineMetrics(entry);

  let social = null;
  if (isSocialConfigured()) {
    social = await getSocialMomentum(entry.baseAsset);
  }

  const onchain = await getOnchainMetrics(entry.symbol, entry.baseAsset);

  return { ...kline, volatilityPct, isNew, social, onchain };
}

function finalizeCoin(entry, metrics) {
  const scoreInput = {
    change24h: entry.change24h,
    change7d: metrics.change7d,
    volatilityPct: metrics.volatilityPct,
    rsi: metrics.rsi,
    volumeRatio: metrics.volumeRatio,
    social: metrics.social,
    onchain: metrics.onchain,
  };
  const { total, breakdown, weights } = computeScore(scoreInput);

  return {
    id: entry.symbol,
    symbol: entry.baseAsset,
    name: entry.baseAsset,
    image: null,
    price: entry.price,
    volume24h: round(entry.volume24h),
    volumeRank: entry.rank ?? null,
    change24h: round(entry.change24h),
    change7d: metrics.change7d != null ? round(metrics.change7d) : null,
    high24h: entry.high24h,
    low24h: entry.low24h,
    volatilityPct: round(metrics.volatilityPct),
    isNew: metrics.isNew,
    rsi: metrics.rsi != null ? round(metrics.rsi) : null,
    macdHistogram: metrics.macdHistogram != null ? round(metrics.macdHistogram, 6) : null,
    volumeRatio: metrics.volumeRatio != null ? round(metrics.volumeRatio) : null,
    social: metrics.social || null,
    socialAvailable: Boolean(metrics.social?.available),
    onchain: metrics.onchain || null,
    onchainAvailable: Boolean(metrics.onchain?.available),
    detailed: true,
    score: total,
    scoreBreakdown: breakdown,
    scoreWeights: weights,
  };
}

/**
 * Runs the full screening pipeline against Binance USDT-M perpetuals:
 *  1. top `detailedCoinsLimit` pairs by 24h quote volume (+ any watchlist
 *     pairs that fell outside that ranking)
 *  2. RSI/MACD/volume-ratio/7d-change from a single daily-klines fetch
 *     per pair, plus optional social/on-chain metrics
 *  3. score every pair and return the sorted list
 * Binance's generous rate limit means every pair in the universe gets
 * full ("detailed") analysis every cycle - no more quick-vs-detailed
 * split like the old CoinGecko-backed pipeline needed.
 */
async function runFullScreening() {
  const { detailedCoinsLimit } = getSettings();
  const universe = await binance.getUniverse(detailedCoinsLimit);

  const watchlistIds = getWatchlistCoinIds();
  const universeIds = new Set(universe.map((u) => u.symbol));
  const missingWatchlist = [];
  for (const id of watchlistIds) {
    if (universeIds.has(id)) continue;
    const snap = await binance.getSymbolSnapshot(id).catch((err) => {
      console.warn(`[screening] watchlist symbol ${id} snapshot failed: ${err.message}`);
      return null;
    });
    if (snap) missingWatchlist.push(snap);
  }

  const fullList = [...universe, ...missingWatchlist].map((entry, i) => ({ ...entry, rank: i + 1 }));

  const results = [];
  for (const entry of fullList) {
    const metrics = await computeSymbolMetrics(entry);
    results.push(finalizeCoin(entry, metrics));
  }

  results.sort((a, b) => b.score - a.score);
  return results;
}

function persistSignals(coins, threshold) {
  const insert = db.prepare(`
    INSERT INTO signals (coin_id, symbol, name, score, price, change_24h, volume_spike, rsi, macd_histogram, volatility, social_score, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
  `);
  const above = coins.filter((c) => c.score >= threshold);
  if (above.length) {
    db.exec('BEGIN');
    try {
      for (const c of above) {
        insert.run(
          c.id,
          c.symbol,
          c.name,
          c.score,
          c.price,
          c.change24h,
          c.volumeRatio,
          c.rsi,
          c.macdHistogram,
          c.volatilityPct,
          c.social?.score ?? null
        );
      }
      db.exec('COMMIT');
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  }
  return above;
}

/** Runs screening, updates the in-memory cache, and returns it. `onDone(result, newSignals)` fires after persistence. */
async function triggerScreening({ threshold, force = false, onDone } = {}) {
  const now = Date.now();
  if (!force && now - lastTriggeredAt < MIN_MANUAL_REFRESH_GAP_MS) {
    return latestScreening;
  }
  if (latestScreening.isRunning) return latestScreening;

  lastTriggeredAt = now;
  latestScreening.isRunning = true;
  try {
    const coins = await runFullScreening();
    latestScreening = { coins, updatedAt: new Date().toISOString(), isRunning: false };

    if (threshold != null) {
      const newSignals = persistSignals(coins, threshold);
      if (onDone) onDone(latestScreening, newSignals);
    } else if (onDone) {
      onDone(latestScreening, []);
    }
    return latestScreening;
  } catch (err) {
    latestScreening.isRunning = false;
    throw err;
  }
}

function getLatestScreening() {
  return latestScreening;
}

module.exports = {
  runFullScreening,
  triggerScreening,
  getLatestScreening,
  persistSignals,
};
