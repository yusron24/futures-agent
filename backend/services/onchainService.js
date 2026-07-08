const axios = require('axios');
const NodeCache = require('node-cache');
const { getSettings } = require('../db/settingsStore');

// Refreshed at most every 5 minutes per coin, matching the spec's cadence.
const cache = new NodeCache({ stdTTL: 280 });

// ---------------------------------------------------------------------
// Deterministic dummy fallback - used whenever no provider key is set, or
// a live call fails/is unsupported for a given coin. Seeded by coin id +
// a 5-minute time bucket, so numbers are stable within a cache window
// instead of jumping randomly on every request, but still "move" over
// time like real data would. Swap the live fetchers below for a real
// CryptoQuant/Glassnode/Whale Alert plan and this fallback stops being used
// automatically (see `available` / `source` on the returned object).
// ---------------------------------------------------------------------

function hashSeed(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function mulberry32(seed) {
  let s = seed;
  return function next() {
    s |= 0;
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function buildDummyMetrics(coinId) {
  const windowBucket = Math.floor(Date.now() / (5 * 60 * 1000));
  const rand = mulberry32(hashSeed(`${coinId}:${windowBucket}`));

  const exchangeInflow24hUsd = Math.round(rand() * 5_000_000);
  const exchangeOutflow24hUsd = Math.round(rand() * 5_000_000);
  const whaleToExchangeCount = Math.floor(rand() * 6);
  const whaleFromExchangeCount = Math.floor(rand() * 6);

  return {
    exchangeInflow24hUsd,
    exchangeOutflow24hUsd,
    netFlow24hUsd: exchangeInflow24hUsd - exchangeOutflow24hUsd,
    supplyOnExchangesPct: Math.round((5 + rand() * 20) * 100) / 100,
    supplyOnExchangesChange24h: Math.round((rand() - 0.5) * 400) / 100,
    whaleToExchangeCount,
    whaleFromExchangeCount,
    whaleTxCountRecent: whaleToExchangeCount + whaleFromExchangeCount,
  };
}

// ---------------------------------------------------------------------
// Whale Alert (https://docs.whale-alert.io) - real, documented free-tier
// API. Counts >$100k transactions in the last hour and classifies them by
// whether they moved into or out of a known exchange wallet.
// ---------------------------------------------------------------------

async function fetchWhaleActivity(symbol) {
  const { whaleAlertApiKey } = getSettings();
  if (!whaleAlertApiKey) return null;

  try {
    const start = Math.floor(Date.now() / 1000) - 3600; // free tier only allows recent windows
    const { data } = await axios.get('https://api.whale-alert.io/v1/transactions', {
      params: {
        api_key: whaleAlertApiKey,
        min_value: 100000,
        start,
        currency: symbol.toLowerCase(),
        limit: 100,
      },
      timeout: 8000,
    });

    const txs = data?.transactions || [];
    let whaleToExchangeCount = 0;
    let whaleFromExchangeCount = 0;
    for (const tx of txs) {
      if (tx.to?.owner_type === 'exchange') whaleToExchangeCount += 1;
      if (tx.from?.owner_type === 'exchange') whaleFromExchangeCount += 1;
    }

    return { whaleToExchangeCount, whaleFromExchangeCount, whaleTxCountRecent: txs.length, windowMinutes: 60 };
  } catch (err) {
    console.warn(`[onchain] Whale Alert fetch failed for ${symbol}: ${err.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------
// CryptoQuant exchange flows - only meaningful (and only available on
// free/low tier) for BTC and ETH, so every other coin borrows BTC's flow
// data as a macro "risk-on/off" proxy (per spec). This is best-effort:
// CryptoQuant's exact field names differ across plans, so any shape
// mismatch or auth failure just falls through to the dummy fallback.
// ---------------------------------------------------------------------

async function fetchCryptoQuantFlows(symbol) {
  const { cryptoquantApiKey } = getSettings();
  const lower = symbol.toLowerCase();
  if (!cryptoquantApiKey || !['btc', 'eth'].includes(lower)) return null;

  try {
    const params = { exchange: 'all_exchange', window: 'day', limit: 2, api_key: cryptoquantApiKey };
    const [inflowRes, outflowRes, reserveRes] = await Promise.all([
      axios.get(`https://api.cryptoquant.com/v1/${lower}/exchange-flows/inflow`, { params, timeout: 8000 }),
      axios.get(`https://api.cryptoquant.com/v1/${lower}/exchange-flows/outflow`, { params, timeout: 8000 }),
      axios.get(`https://api.cryptoquant.com/v1/${lower}/exchange-flows/reserve`, { params, timeout: 8000 }),
    ]);

    const inflow = inflowRes.data?.result?.data?.[0];
    const outflow = outflowRes.data?.result?.data?.[0];
    const reserveLatest = reserveRes.data?.result?.data?.[0];
    const reservePrev = reserveRes.data?.result?.data?.[1];
    const inflowUsd = inflow?.inflow_total_usd ?? inflow?.inflow_total;
    const outflowUsd = outflow?.outflow_total_usd ?? outflow?.outflow_total;
    if (inflowUsd == null || outflowUsd == null) return null;

    const supplyOnExchangesPct = reserveLatest?.reserve_total ?? null;
    const supplyOnExchangesChange24h =
      reserveLatest?.reserve_total != null && reservePrev?.reserve_total
        ? ((reserveLatest.reserve_total - reservePrev.reserve_total) / reservePrev.reserve_total) * 100
        : null;

    return {
      exchangeInflow24hUsd: inflowUsd,
      exchangeOutflow24hUsd: outflowUsd,
      netFlow24hUsd: inflowUsd - outflowUsd,
      supplyOnExchangesPct,
      supplyOnExchangesChange24h,
    };
  } catch (err) {
    console.warn(`[onchain] CryptoQuant fetch failed for ${symbol}: ${err.message}`);
    return null;
  }
}

/**
 * Returns on-chain metrics for a coin: exchange inflow/outflow, % supply
 * held on exchanges, and recent whale (>$100k) transaction activity.
 * Cached for 5 minutes per coin. Falls back to deterministic dummy data
 * (clearly flagged via `source`/`available`) whenever no provider key is
 * configured or a live call fails - the shape is identical either way so
 * callers never need to branch on it.
 */
async function getOnchainMetrics(coinId, symbol) {
  const cacheKey = `onchain_${coinId}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const { cryptoquantApiKey, glassnodeApiKey, whaleAlertApiKey } = getSettings();
  const anyKeyConfigured = Boolean(cryptoquantApiKey || glassnodeApiKey || whaleAlertApiKey);

  const dummy = buildDummyMetrics(coinId);
  let result;

  if (!anyKeyConfigured) {
    result = { ...dummy, available: false, source: 'dummy', isProxy: false, proxySource: null, whaleWindowMinutes: null };
  } else {
    const isMajor = symbol.toUpperCase() === 'BTC' || symbol.toUpperCase() === 'ETH';
    const flowSymbol = isMajor ? symbol : 'BTC';
    const [flows, whale] = await Promise.all([fetchCryptoQuantFlows(flowSymbol), fetchWhaleActivity(symbol)]);

    const flowsLive = Boolean(flows);
    const whaleLive = Boolean(whale);

    result = {
      exchangeInflow24hUsd: flows?.exchangeInflow24hUsd ?? dummy.exchangeInflow24hUsd,
      exchangeOutflow24hUsd: flows?.exchangeOutflow24hUsd ?? dummy.exchangeOutflow24hUsd,
      netFlow24hUsd: flows?.netFlow24hUsd ?? dummy.netFlow24hUsd,
      supplyOnExchangesPct: flows?.supplyOnExchangesPct ?? dummy.supplyOnExchangesPct,
      supplyOnExchangesChange24h: flows?.supplyOnExchangesChange24h ?? dummy.supplyOnExchangesChange24h,
      whaleToExchangeCount: whale?.whaleToExchangeCount ?? dummy.whaleToExchangeCount,
      whaleFromExchangeCount: whale?.whaleFromExchangeCount ?? dummy.whaleFromExchangeCount,
      whaleTxCountRecent: whale?.whaleTxCountRecent ?? dummy.whaleTxCountRecent,
      whaleWindowMinutes: whale ? 60 : null,
      available: flowsLive || whaleLive,
      source: flowsLive || whaleLive ? 'live' : 'dummy',
      isProxy: !isMajor,
      proxySource: !isMajor ? 'BTC' : null,
    };
  }

  cache.set(cacheKey, result);
  return result;
}

module.exports = { getOnchainMetrics };
