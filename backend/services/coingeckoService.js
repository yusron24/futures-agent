const NodeCache = require('node-cache');
const { getWithRetry, sleep } = require('../utils/httpClient');

const cache = new NodeCache({ stdTTL: 60 });

// Common stablecoins / wrapped or liquid-staking derivative tokens to
// exclude from screening (they don't have meaningful "breakout" potential).
const STABLECOIN_SYMBOLS = new Set([
  'usdt', 'usdc', 'dai', 'busd', 'tusd', 'usdp', 'fdusd', 'usdd', 'frax',
  'gusd', 'lusd', 'usde', 'pyusd', 'usdj', 'eurt', 'eurs', 'usdx', 'susd',
  'crvusd', 'dola', 'mim',
]);
const WRAPPED_SYMBOLS = new Set([
  'wbtc', 'weth', 'wbnb', 'wsteth', 'steth', 'reth', 'cbeth', 'wavax',
  'wmatic', 'weeth', 'meth', 'sweth', 'wtrx', 'wsol',
]);

function isStableOrWrapped(coin) {
  const symbol = (coin.symbol || '').toLowerCase();
  if (STABLECOIN_SYMBOLS.has(symbol) || WRAPPED_SYMBOLS.has(symbol)) return true;
  // Heuristic fallback: pegged very close to $1 with a name hinting "usd"/"stable"
  const name = (coin.name || '').toLowerCase();
  const looksStableName = name.includes('usd') || name.includes('stable') || name.includes('wrapped');
  const peggedToDollar = coin.current_price > 0.98 && coin.current_price < 1.02;
  if (looksStableName && peggedToDollar) return true;
  if (name.startsWith('wrapped ')) return true;
  return false;
}

/** Top N coins by market cap (default 250), stablecoins/wrapped tokens excluded. */
async function getTopCoins(limit = 250) {
  const cacheKey = `top_coins_${limit}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const perPage = Math.min(limit, 250);
  const data = await getWithRetry('/coins/markets', {
    params: {
      vs_currency: 'usd',
      order: 'market_cap_desc',
      per_page: perPage,
      page: 1,
      sparkline: false,
      price_change_percentage: '1h,24h,7d',
    },
  });

  const filtered = data.filter((c) => !isStableOrWrapped(c));
  cache.set(cacheKey, filtered, 55);
  return filtered;
}

/** 7/30-day market chart (prices + volumes) for a single coin id. */
async function getCoinMarketChart(id, days = 30) {
  const cacheKey = `chart_${id}_${days}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const data = await getWithRetry(`/coins/${id}/market_chart`, {
    params: { vs_currency: 'usd', days },
  });
  cache.set(cacheKey, data, 280); // ~ just under the 5-min scan cycle
  return data;
}

/** Full coin detail (description, links, genesis date, ATH/ATL, etc). */
async function getCoinDetail(id) {
  const cacheKey = `detail_${id}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const data = await getWithRetry(`/coins/${id}`, {
    params: {
      localization: false,
      tickers: false,
      market_data: true,
      community_data: true,
      developer_data: false,
      sparkline: true,
    },
  });
  cache.set(cacheKey, data, 55);
  return data;
}

/** List of all coin categories (id + name). */
async function getCategories() {
  const cacheKey = 'categories_list';
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const data = await getWithRetry('/coins/categories/list');
  cache.set(cacheKey, data, 60 * 60 * 6); // categories barely change, cache 6h
  return data;
}

/** Coins belonging to a given category id, market data sorted by market cap. */
async function getCoinsByCategory(categoryId, limit = 250) {
  const cacheKey = `category_${categoryId}_${limit}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  const data = await getWithRetry('/coins/markets', {
    params: {
      vs_currency: 'usd',
      category: categoryId,
      order: 'market_cap_desc',
      per_page: Math.min(limit, 250),
      page: 1,
      sparkline: false,
      price_change_percentage: '1h,24h,7d',
    },
  });
  const filtered = data.filter((c) => !isStableOrWrapped(c));
  cache.set(cacheKey, filtered, 120);
  return filtered;
}

module.exports = {
  cache,
  sleep,
  isStableOrWrapped,
  getTopCoins,
  getCoinMarketChart,
  getCoinDetail,
  getCategories,
  getCoinsByCategory,
};
