const NodeCache = require('node-cache');
const { getWithRetry } = require('../utils/binanceClient');

const cache = new NodeCache({ stdTTL: 60 });

// Stablecoin-vs-USDT and similar non-altcoin pairs occasionally listed
// on Binance Futures - excluded the same way stablecoins were filtered
// out of the old CoinGecko universe.
const EXCLUDED_BASE_ASSETS = new Set(['USDC', 'BUSD', 'TUSD', 'FDUSD', 'USDP', 'DAI']);

async function getExchangeInfo() {
  const cached = cache.get('exchange_info');
  if (cached) return cached;
  const data = await getWithRetry('/fapi/v1/exchangeInfo');
  cache.set('exchange_info', data, 60 * 60); // symbol list/onboard dates barely change
  return data;
}

async function getAllTickers24hr() {
  const cached = cache.get('tickers_24hr');
  if (cached) return cached;
  const data = await getWithRetry('/fapi/v1/ticker/24hr');
  cache.set('tickers_24hr', data, 50);
  return data;
}

function isEligibleSymbol(s) {
  return (
    s.contractType === 'PERPETUAL' &&
    s.quoteAsset === 'USDT' &&
    s.status === 'TRADING' &&
    !EXCLUDED_BASE_ASSETS.has(s.baseAsset)
  );
}

/**
 * Universe of tradable USDT-margined perpetual pairs, ranked by 24h quote
 * volume (the closest Binance equivalent to CoinGecko's market-cap
 * ranking - Binance has no market cap data), top N.
 */
async function getUniverse(limit = 150) {
  const [exchangeInfo, tickers] = await Promise.all([getExchangeInfo(), getAllTickers24hr()]);

  const symbolMeta = new Map();
  for (const s of exchangeInfo.symbols) {
    if (isEligibleSymbol(s)) symbolMeta.set(s.symbol, s);
  }

  const merged = tickers
    .filter((t) => symbolMeta.has(t.symbol))
    .map((t) => {
      const meta = symbolMeta.get(t.symbol);
      return {
        symbol: t.symbol,
        baseAsset: meta.baseAsset,
        onboardDate: meta.onboardDate,
        price: parseFloat(t.lastPrice),
        change24h: parseFloat(t.priceChangePercent),
        high24h: parseFloat(t.highPrice),
        low24h: parseFloat(t.lowPrice),
        volume24h: parseFloat(t.quoteVolume),
      };
    })
    .filter((c) => Number.isFinite(c.price) && c.price > 0)
    .sort((a, b) => b.volume24h - a.volume24h);

  return merged.slice(0, limit);
}

/** Daily klines (OHLCV) for a symbol - source for RSI/MACD/volume-ratio/7d-change. */
async function getDailyKlines(symbol, limit = 40) {
  const cacheKey = `klines_d_${symbol}_${limit}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;
  const data = await getWithRetry('/fapi/v1/klines', { params: { symbol, interval: '1d', limit } });
  cache.set(cacheKey, data, 280);
  return data;
}

/** Hourly klines for the coin-detail price chart (last N hours). */
async function getHourlyKlines(symbol, limit = 168) {
  const cacheKey = `klines_h_${symbol}_${limit}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;
  const data = await getWithRetry('/fapi/v1/klines', { params: { symbol, interval: '1h', limit } });
  cache.set(cacheKey, data, 280);
  return data;
}

/** Fresh single-symbol snapshot (not from the cached top-N universe list) - used for watchlist coins outside the top ranking and the coin detail page. */
async function getSymbolSnapshot(symbol) {
  const [exchangeInfo, ticker] = await Promise.all([
    getExchangeInfo(),
    getWithRetry('/fapi/v1/ticker/24hr', { params: { symbol } }),
  ]);
  const meta = exchangeInfo.symbols.find((s) => s.symbol === symbol);
  if (!meta) return null;
  return {
    symbol: ticker.symbol,
    baseAsset: meta.baseAsset,
    onboardDate: meta.onboardDate,
    price: parseFloat(ticker.lastPrice),
    change24h: parseFloat(ticker.priceChangePercent),
    high24h: parseFloat(ticker.highPrice),
    low24h: parseFloat(ticker.lowPrice),
    volume24h: parseFloat(ticker.quoteVolume),
  };
}

module.exports = { getUniverse, getDailyKlines, getHourlyKlines, getSymbolSnapshot };
