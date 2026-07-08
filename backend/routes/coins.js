const express = require('express');
const binance = require('../services/binanceService');
const { triggerScreening, getLatestScreening } = require('../services/screeningService');
const { getOnchainMetrics } = require('../services/onchainService');
const { computeScore } = require('../services/scoringService');
const { getSettings } = require('../db/settingsStore');

const router = express.Router();

function applyFilters(coins, query) {
  let result = coins;
  const minVolume24h = query.minVolume24h ? Number(query.minVolume24h) : null;
  if (minVolume24h) result = result.filter((c) => (c.volume24h || 0) >= minVolume24h);
  if (query.newOnly === 'true') result = result.filter((c) => c.isNew);
  if (query.minScore) result = result.filter((c) => c.score >= Number(query.minScore));
  return result;
}

// GET /api/coins/screening?minVolume24h=&newOnly=&minScore=&refresh=true
router.get('/screening', async (req, res) => {
  try {
    const { signalScoreThreshold } = getSettings();

    if (req.query.refresh === 'true') {
      await triggerScreening({ threshold: signalScoreThreshold, force: false });
    }

    const latest = getLatestScreening();
    return res.json({
      success: true,
      updatedAt: latest.updatedAt,
      isRunning: latest.isRunning,
      threshold: signalScoreThreshold,
      count: latest.coins.length,
      coins: applyFilters(latest.coins, req.query),
    });
  } catch (err) {
    console.error('[route:/api/coins/screening]', err.message);
    res.status(502).json({ success: false, error: 'Failed to load screening data. Binance may be rate-limiting requests, please retry shortly.' });
  }
});

// GET /api/coins/:id - full detail + 7d chart + indicators for the detail page. :id is the Binance symbol (e.g. BTCUSDT).
router.get('/:id', async (req, res) => {
  try {
    const symbol = req.params.id.toUpperCase();
    const [snapshot, hourlyKlines] = await Promise.all([
      binance.getSymbolSnapshot(symbol),
      binance.getHourlyKlines(symbol, 168),
    ]);

    if (!snapshot) {
      return res.status(404).json({ success: false, error: 'Symbol not found on Binance Futures.' });
    }

    // Fetched on demand so the detail page always has fresh on-chain data,
    // even for pairs that weren't in the latest screening cycle.
    const onchain = await getOnchainMetrics(symbol, snapshot.baseAsset);

    const latest = getLatestScreening();
    const cachedEntry = latest.coins.find((c) => c.id === symbol) || null;

    let screeningEntry = cachedEntry;
    if (cachedEntry) {
      const { total, breakdown, weights } = computeScore({
        change24h: cachedEntry.change24h,
        change7d: cachedEntry.change7d,
        volatilityPct: cachedEntry.volatilityPct,
        rsi: cachedEntry.rsi,
        volumeRatio: cachedEntry.volumeRatio,
        social: cachedEntry.social,
        onchain,
      });
      screeningEntry = {
        ...cachedEntry,
        onchain,
        onchainAvailable: Boolean(onchain?.available),
        score: total,
        scoreBreakdown: breakdown,
        scoreWeights: weights,
      };
    }

    const daysSinceOnboard = snapshot.onboardDate ? (Date.now() - snapshot.onboardDate) / 86400000 : null;

    res.json({
      success: true,
      coin: {
        id: symbol,
        symbol: snapshot.baseAsset,
        name: snapshot.baseAsset,
        price: snapshot.price,
        high24h: snapshot.high24h,
        low24h: snapshot.low24h,
        change24h: snapshot.change24h,
        change7d: screeningEntry?.change7d ?? null,
        volume24h: snapshot.volume24h,
        onboardDate: snapshot.onboardDate,
        isNew: daysSinceOnboard != null ? daysSinceOnboard <= 30 : false,
      },
      chart: {
        prices: hourlyKlines.map((k) => [k[0], parseFloat(k[4])]),
        volumes: hourlyKlines.map((k) => [k[0], parseFloat(k[7])]),
      },
      onchain,
      screening: screeningEntry,
    });
  } catch (err) {
    console.error(`[route:/api/coins/${req.params.id}]`, err.message);
    res.status(502).json({ success: false, error: 'Failed to load coin detail from Binance.' });
  }
});

module.exports = router;
