const NodeCache = require('node-cache');
const binance = require('./binanceService');
const { calculateRSI } = require('./indicators');
const { getLatestScreening } = require('./screeningService');
const { getSettings } = require('../db/settingsStore');

const cache = new NodeCache();

const SUPPORTED_INTERVALS = ['15m', '1h', '4h', '1d', '1w'];
const DEFAULT_INTERVAL = '1d';

// How long a non-daily RSI sweep is cached before recomputing - scaled
// roughly to how fast each timeframe actually moves, so shorter
// timeframes stay fresher without re-scanning the whole universe on
// every 30s poll.
const CACHE_TTL_SECONDS = { '15m': 30, '1h': 90, '4h': 300, '1w': 900 };

/** For '1d' we reuse the main screening cycle's already-computed daily RSI - zero extra Binance calls. */
function resultsFromMainScreening() {
  const latest = getLatestScreening();
  const coins = latest.coins
    .filter((c) => c.rsi != null)
    .map((c) => ({ id: c.id, symbol: c.symbol, name: c.name, price: c.price, change24h: c.change24h, rsi: c.rsi }));
  return { updatedAt: latest.updatedAt, poolSize: latest.coins.length, coins };
}

/** For any other interval, fetch klines for the universe fresh (cached per-interval) and compute RSI(14). */
async function resultsFromFreshScan(interval) {
  const cacheKey = `rsi_scan_${interval}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const { detailedCoinsLimit } = getSettings();
  const universe = await binance.getUniverse(detailedCoinsLimit);

  const coins = [];
  for (const entry of universe) {
    try {
      const klines = await binance.getKlines(entry.symbol, interval, 40);
      const closes = klines.map((k) => parseFloat(k[4]));
      const rsi = calculateRSI(closes, 14);
      if (rsi != null) {
        coins.push({
          id: entry.symbol,
          symbol: entry.baseAsset,
          name: entry.baseAsset,
          price: entry.price,
          change24h: entry.change24h,
          rsi: Math.round(rsi * 100) / 100,
        });
      }
    } catch (err) {
      console.warn(`[rsi-screener] ${interval} klines failed for ${entry.symbol}: ${err.message}`);
    }
  }

  const result = { updatedAt: new Date().toISOString(), poolSize: universe.length, coins };
  cache.set(cacheKey, result, CACHE_TTL_SECONDS[interval] || 90);
  return result;
}

/**
 * Coins currently oversold (RSI<30) / overbought (RSI>70) for the given
 * timeframe. '1d' is free (reuses the main screening cycle); every other
 * supported interval (15m/1h/4h/1w) triggers its own klines sweep across
 * the universe, cached briefly so repeated polls don't re-fetch.
 */
async function getRsiScreenerResults({ interval } = {}) {
  const tf = SUPPORTED_INTERVALS.includes(interval) ? interval : DEFAULT_INTERVAL;
  const { updatedAt, poolSize, coins } = tf === '1d' ? resultsFromMainScreening() : await resultsFromFreshScan(tf);

  const oversold = coins.filter((c) => c.rsi < 30).sort((a, b) => a.rsi - b.rsi);
  const overbought = coins.filter((c) => c.rsi > 70).sort((a, b) => b.rsi - a.rsi);

  return {
    interval: tf,
    updatedAt,
    poolSize,
    scannedCount: coins.length,
    oversold,
    overbought,
  };
}

module.exports = { getRsiScreenerResults, SUPPORTED_INTERVALS };
