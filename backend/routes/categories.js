const express = require('express');
const { getCategories } = require('../services/coingeckoService');

const router = express.Router();

// GET /api/categories
router.get('/', async (req, res) => {
  try {
    const categories = await getCategories();
    res.json({ success: true, categories });
  } catch (err) {
    console.error('[route:/api/categories]', err.message);
    res.status(502).json({ success: false, error: 'Failed to load categories from CoinGecko.' });
  }
});

module.exports = router;
