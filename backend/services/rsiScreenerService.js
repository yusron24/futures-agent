const binance = require('./binanceService');
const { calculateRSI } = require('./indicators');
const { getLatestScreening } = require('./screeningService');
const { getSettings } = require('../db/settingsStore');
const { mapWithConcurrency } = require('../utils/concurrency');

const SUPPORTED_INTERVALS = ['15m', '1h', '4h', '1d', '1w'];
const DEFAULT_INTERVAL = '1d';
const SWEEP_CONCURRENCY = 6;

// How long a sweep's result is considered fresh before a request (or the
// post-cycle prewarm) kicks off a new background sweep - scaled to how
// fast each timeframe actually moves.
const FRESH_MS = {
  '15m': 60_000,
  '1h': 180_000,
  '4h': 600_000,
  '1w': 1_800_000,
};

// interval -> { data, inFlight, progress }. The API always answers from
// `data` immediately (stale-while-revalidate); sweeps only ever run in
// the background, so /api/rsi-screener never blocks on Binance no matter
// how many pairs the universe has.
const sweeps = new Map();

function getState(tf) {
  if (!sweeps.has(tf)) sweeps.set(tf, { data: null, inFlight: null, progress: null });
  return sweeps.get(tf);
}

async function runSweep(tf) {
  const state = getState(tf);
  const { detailedCoinsLimit } = getSettings();
  const universe = await binance.getUniverse(detailedCoinsLimit);
  state.progress = { done: 0, total: universe.length };

  const coins = [];
  await mapWithConcurrency(universe, SWEEP_CONCURRENCY, async (entry) => {
    try {
      const klines = await binance.getKlines(entry.symbol, tf, 40);
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
      console.warn(`[rsi-screener] ${tf} klines failed for ${entry.symbol}: ${err.message}`);
    } finally {
      state.progress.done += 1;
    }
  });

  state.data = { updatedAt: new Date().toISOString(), poolSize: universe.length, coins };
  return state.data;
}

/** Starts a background sweep for `tf` if its data is stale/missing and none is already running. */
function ensureFresh(tf) {
  const state = getState(tf);
  const isFresh =
    state.data && Date.now() - Date.parse(state.data.updatedAt) < (FRESH_MS[tf] ?? 180_000);
  if (!isFresh && !state.inFlight) {
    state.inFlight = runSweep(tf)
      .catch((err) => console.error(`[rsi-screener] ${tf} sweep failed: ${err.message}`))
      .finally(() => {
        state.inFlight = null;
        state.progress = null;
      });
  }
  return state;
}

function classify(coins) {
  const oversold = coins.filter((c) => c.rsi < 30).sort((a, b) => a.rsi - b.rsi);
  const overbought = coins.filter((c) => c.rsi > 70).sort((a, b) => b.rsi - a.rsi);
  return { oversold, overbought };
}

/**
 * Coins currently oversold (RSI<30) / overbought (RSI>70) for a given
 * timeframe. Always answers immediately: '1d' reads straight off the
 * main screening cycle; other intervals serve the last sweep's result
 * (marked `isRefreshing` + `progress` while a new one runs in the
 * background). First-ever request for an interval returns an empty list
 * with `isRefreshing: true` - the frontend polls until the sweep lands.
 */
async function getRsiScreenerResults({ interval } = {}) {
  const tf = SUPPORTED_INTERVALS.includes(interval) ? interval : DEFAULT_INTERVAL;

  let data;
  let isRefreshing;
  let progress = null;

  if (tf === '1d') {
    const latest = getLatestScreening();
    data = {
      updatedAt: latest.updatedAt,
      poolSize: latest.coins.length,
      coins: latest.coins
        .filter((c) => c.rsi != null)
        .map((c) => ({ id: c.id, symbol: c.symbol, name: c.name, price: c.price, change24h: c.change24h, rsi: c.rsi })),
    };
    isRefreshing = latest.isRunning;
  } else {
    const state = ensureFresh(tf);
    data = state.data ?? { updatedAt: null, poolSize: state.progress?.total ?? 0, coins: [] };
    isRefreshing = Boolean(state.inFlight);
    progress = state.progress;
  }

  const { oversold, overbought } = classify(data.coins);

  return {
    interval: tf,
    updatedAt: data.updatedAt,
    poolSize: data.poolSize,
    scannedCount: data.coins.length,
    isRefreshing,
    progress,
    oversold,
    overbought,
  };
}

let prewarmRunning = false;

/**
 * Refreshes every stale non-daily timeframe in the background, one sweep
 * at a time. Called after each main screening cycle so users switching
 * timeframes almost always hit warm data instead of waiting on a sweep.
 */
async function prewarmRsiTimeframes() {
  if (prewarmRunning) return;
  prewarmRunning = true;
  try {
    for (const tf of SUPPORTED_INTERVALS) {
      if (tf === '1d') continue;
      const state = ensureFresh(tf);
      if (state.inFlight) await state.inFlight;
    }
  } finally {
    prewarmRunning = false;
  }
}

module.exports = { getRsiScreenerResults, prewarmRsiTimeframes, SUPPORTED_INTERVALS };
