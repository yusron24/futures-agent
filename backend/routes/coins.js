const express = require('express');
const coingecko = require('../services/coingeckoService');
const { triggerScreening, getLatestScreening, runFullScreening } = require('../services/screeningService');
const { THRESHOLD } = require('../services/scheduler');

const router = express.Router();

function applyFilters(coins, query) {
  let result = coins;
  const minMarketCap = query.minMarketCap ? Number(query.minMarketCap) : null;
  if (minMarketCap) result = result.filter((c) => (c.marketCap || 0) >= minMarketCap);
  if (query.newOnly === 'true') result = result.filter((c) => c.isNew);
  if (query.minScore) result = result.filter((c) => c.score >= Number(query.minScore));
  return result;
}

// GET /api/coins/screening?minMarketCap=&newOnly=&category=&minScore=&refresh=true
router.get('/screening', async (req, res) => {
  try {
    const { category } = req.query;

    if (category) {
      // Category screening is computed on demand (not part of the 5-min global cache)
      const coins = await runFullScreening({ category });
      return res.json({
        success: true,
        updatedAt: new Date().toISOString(),
        category,
        threshold: THRESHOLD,
        count: coins.length,
        coins: applyFilters(coins, req.query),
      });
    }

    if (req.query.refresh === 'true') {
      await triggerScreening({ threshold: THRESHOLD, force: false });
    }

    const latest = getLatestScreening();
    return res.json({
      success: true,
      updatedAt: latest.updatedAt,
      isRunning: latest.isRunning,
      threshold: THRESHOLD,
      count: latest.coins.length,
      coins: applyFilters(latest.coins, req.query),
    });
  } catch (err) {
    console.error('[route:/api/coins/screening]', err.message);
    res.status(502).json({ success: false, error: 'Failed to load screening data. CoinGecko may be rate-limiting requests, please retry shortly.' });
  }
});

// GET /api/coins/:id - full detail + 7d chart + indicators for the detail page
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [detail, chart] = await Promise.all([
      coingecko.getCoinDetail(id),
      coingecko.getCoinMarketChart(id, 7),
    ]);

    const latest = getLatestScreening();
    const screeningEntry = latest.coins.find((c) => c.id === id) || null;

    res.json({
      success: true,
      coin: {
        id: detail.id,
        symbol: (detail.symbol || '').toUpperCase(),
        name: detail.name,
        image: detail.image?.large,
        description: detail.description?.en?.slice(0, 500) || '',
        marketCap: detail.market_data?.market_cap?.usd,
        marketCapRank: detail.market_cap_rank,
        price: detail.market_data?.current_price?.usd,
        high24h: detail.market_data?.high_24h?.usd,
        low24h: detail.market_data?.low_24h?.usd,
        change1h: detail.market_data?.price_change_percentage_1h_in_currency?.usd,
        change24h: detail.market_data?.price_change_percentage_24h,
        change7d: detail.market_data?.price_change_percentage_7d,
        ath: detail.market_data?.ath?.usd,
        atl: detail.market_data?.atl?.usd,
        atlDate: detail.market_data?.atl_date?.usd,
      },
      chart: {
        prices: chart.prices || [],
        volumes: chart.total_volumes || [],
      },
      screening: screeningEntry,
    });
  } catch (err) {
    console.error(`[route:/api/coins/${req.params.id}]`, err.message);
    res.status(502).json({ success: false, error: 'Failed to load coin detail from CoinGecko.' });
  }
});

module.exports = router;
