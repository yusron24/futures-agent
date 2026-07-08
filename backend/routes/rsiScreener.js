const express = require('express');
const { getRsiScreenerResults } = require('../services/rsiScreenerService');

const router = express.Router();

// GET /api/rsi-screener -> coins currently oversold (RSI<30) / overbought (RSI>70)
router.get('/', (req, res) => {
  res.json({ success: true, ...getRsiScreenerResults() });
});

module.exports = router;
