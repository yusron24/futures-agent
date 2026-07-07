const db = require('../db/database');
const coingecko = require('./coingeckoService');
const { getTopCoins, getCoinsByCategory, sleep } = coingecko;
const { calculateRSI, calculateMACD, calculateVolatility, toDailySeries } = require('./indicators');
const { computeScore } = require('./scoringService');
const { getSocialMomentum, socialConfigured } = require('./socialService');

const DETAILED_LIMIT = parseInt(process.env.DETAILED_COINS_LIMIT || '60', 10);
const FETCH_DELAY_MS = parseInt(process.env.DETAILED_FETCH_DELAY_MS || '1300', 10);
const NEW_LISTING_DAYS = 30;

let latestScreening = { coins: [], updatedAt: null, isRunning: false };
let lastTriggeredAt = 0;
const MIN_MANUAL_REFRESH_GAP_MS = 15000;

function getWatchlistCoinIds() {
  const rows = db.prepare('SELECT coin_id FROM watchlist').all();
  return new Set(rows.map((r) => r.coin_id));
}

/** Cheap metrics available directly from the /coins/markets payload - no extra API calls. */
function buildQuickMetrics(coin) {
  const change1h = coin.price_change_percentage_1h_in_currency ?? 0;
  const change24h = coin.price_change_percentage_24h_in_currency ?? coin.price_change_percentage_24h ?? 0;
  const change7d = coin.price_change_percentage_7d_in_currency ?? 0;
  const avgPrice = ((coin.high_24h || coin.current_price) + (coin.low_24h || coin.current_price)) / 2;
  const volatilityPct = calculateVolatility(coin.high_24h || coin.current_price, coin.low_24h || coin.current_price, avgPrice);

  // Heuristic: a very recent all-time-low date usually means the coin has
  // little trading history yet (i.e. it's a fresh listing). Not perfect,
  // but it's the only "recency" signal CoinGecko's markets endpoint gives
  // us for free (no extra API calls needed).
  let isNew = false;
  if (coin.atl_date) {
    const daysSinceAtl = (Date.now() - new Date(coin.atl_date).getTime()) / 86400000;
    isNew = daysSinceAtl <= NEW_LISTING_DAYS;
  }

  const candidateHeuristic = Math.abs(change1h) * 3 + Math.abs(change24h) + volatilityPct;

  return {
    id: coin.id,
    symbol: (coin.symbol || '').toUpperCase(),
    name: coin.name,
    image: coin.image,
    price: coin.current_price,
    marketCap: coin.market_cap,
    marketCapRank: coin.market_cap_rank,
    volume24h: coin.total_volume,
    high24h: coin.high_24h,
    low24h: coin.low_24h,
    change1h,
    change24h,
    change7d,
    volatilityPct,
    isNew,
    _candidateHeuristic: candidateHeuristic,
  };
}

/** Expensive metrics that require an extra CoinGecko call (historical chart) + optional social lookup. */
async function fetchDetailedMetrics(quick) {
  try {
    const chart = await coingecko.getCoinMarketChart(quick.id, 30);
    const dailyCloses = toDailySeries(chart.prices || []);
    const dailyVolumes = toDailySeries(chart.total_volumes || []);

    const rsi = calculateRSI(dailyCloses, 14);
    const macd = calculateMACD(dailyCloses, 12, 26, 9);

    let volumeRatio = null;
    if (dailyVolumes.length >= 2) {
      const latest = dailyVolumes[dailyVolumes.length - 1];
      const prior = dailyVolumes.slice(0, -1);
      const avgPrior = prior.reduce((a, b) => a + b, 0) / prior.length;
      volumeRatio = avgPrior > 0 ? latest / avgPrior : null;
    }

    let social = null;
    if (socialConfigured) {
      social = await getSocialMomentum(quick.symbol);
    }

    return {
      rsi,
      macdHistogram: macd ? macd.histogram : null,
      macd,
      volumeRatio,
      social,
      detailed: true,
    };
  } catch (err) {
    console.warn(`[screening] detailed metrics failed for ${quick.id}: ${err.message}`);
    return { rsi: null, macdHistogram: null, macd: null, volumeRatio: null, social: null, detailed: false };
  }
}

function finalizeCoin(quick, detail) {
  const metrics = {
    change1h: quick.change1h,
    change24h: quick.change24h,
    change7d: quick.change7d,
    volatilityPct: quick.volatilityPct,
    rsi: detail?.rsi ?? null,
    volumeRatio: detail?.volumeRatio ?? null,
    social: detail?.social ?? null,
  };
  const { total, breakdown } = computeScore(metrics);

  return {
    id: quick.id,
    symbol: quick.symbol,
    name: quick.name,
    image: quick.image,
    price: quick.price,
    marketCap: quick.marketCap,
    marketCapRank: quick.marketCapRank,
    volume24h: quick.volume24h,
    change1h: round(quick.change1h),
    change24h: round(quick.change24h),
    change7d: round(quick.change7d),
    volatilityPct: round(quick.volatilityPct),
    isNew: quick.isNew,
    rsi: detail?.rsi != null ? round(detail.rsi) : null,
    macdHistogram: detail?.macdHistogram != null ? round(detail.macdHistogram, 6) : null,
    volumeRatio: detail?.volumeRatio != null ? round(detail.volumeRatio) : null,
    social: detail?.social || null,
    socialAvailable: Boolean(detail?.social?.available),
    detailed: Boolean(detail?.detailed),
    score: total,
    scoreBreakdown: breakdown,
  };
}

function round(n, digits = 2) {
  if (n == null || Number.isNaN(n)) return null;
  const factor = 10 ** digits;
  return Math.round(n * factor) / factor;
}

/**
 * Runs the full screening pipeline:
 *  1. fetch top coins (or a category's coins)
 *  2. compute cheap metrics for all of them
 *  3. pick the top movers (+ any watchlist coins) for expensive, detailed
 *     indicator analysis (RSI/MACD/volume-spike/social) - kept small on
 *     purpose to respect CoinGecko's free-tier rate limit
 *  4. score every coin and return the sorted list
 */
async function runFullScreening({ category } = {}) {
  const coins = category ? await getCoinsByCategory(category) : await getTopCoins(250);
  const watchlistIds = getWatchlistCoinIds();

  const quickList = coins.map(buildQuickMetrics);
  const byHeuristic = [...quickList].sort((a, b) => b._candidateHeuristic - a._candidateHeuristic);
  const detailedIds = new Set(byHeuristic.slice(0, DETAILED_LIMIT).map((c) => c.id));
  watchlistIds.forEach((id) => detailedIds.add(id));

  const results = [];
  let isFirst = true;
  for (const quick of quickList) {
    if (detailedIds.has(quick.id)) {
      if (!isFirst) await sleep(FETCH_DELAY_MS);
      isFirst = false;
      const detail = await fetchDetailedMetrics(quick);
      results.push(finalizeCoin(quick, detail));
    } else {
      results.push(finalizeCoin(quick, null));
    }
  }

  results.sort((a, b) => b.score - a.score);
  return results;
}

function persistSignals(coins, threshold) {
  const insert = db.prepare(`
    INSERT INTO signals (coin_id, symbol, name, score, price, change_24h, volume_spike, rsi, macd_histogram, volatility, social_score, created_at)
    VALUES (@coin_id, @symbol, @name, @score, @price, @change_24h, @volume_spike, @rsi, @macd_histogram, @volatility, @social_score, datetime('now'))
  `);
  const above = coins.filter((c) => c.score >= threshold);
  const tx = db.transaction((rows) => {
    for (const c of rows) {
      insert.run({
        coin_id: c.id,
        symbol: c.symbol,
        name: c.name,
        score: c.score,
        price: c.price,
        change_24h: c.change24h,
        volume_spike: c.volumeRatio,
        rsi: c.rsi,
        macd_histogram: c.macdHistogram,
        volatility: c.volatilityPct,
        social_score: c.social?.score ?? null,
      });
    }
  });
  if (above.length) tx(above);
  return above;
}

/** Runs screening, updates the in-memory cache, and returns it. `onDone(result, newSignals)` fires after persistence. */
async function triggerScreening({ category, threshold, force = false, onDone } = {}) {
  const now = Date.now();
  if (!force && now - lastTriggeredAt < MIN_MANUAL_REFRESH_GAP_MS) {
    return latestScreening;
  }
  if (latestScreening.isRunning) return latestScreening;

  lastTriggeredAt = now;
  latestScreening.isRunning = true;
  try {
    const coins = await runFullScreening({ category });
    latestScreening = { coins, updatedAt: new Date().toISOString(), isRunning: false };

    if (!category && threshold != null) {
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
