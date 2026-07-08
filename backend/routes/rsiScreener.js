const express = require('express');
const { getRsiScreenerResults, SUPPORTED_INTERVALS } = require('../services/rsiScreenerService');

const router = express.Router();

// GET /api/rsi-screener?interval=15m|1h|4h|1d|1w -> coins currently oversold (RSI<30) / overbought (RSI>70)
router.get('/', async (req, res) => {
  try {
    const result = await getRsiScreenerResults({ interval: req.query.interval });
    res.json({ success: true, supportedIntervals: SUPPORTED_INTERVALS, ...result });
  } catch (err) {
    console.error('[route:/api/rsi-screener]', err.message);
    res.status(502).json({ success: false, error: 'Failed to load RSI screener data from Binance.' });
  }
});

module.exports = router;
