const express = require('express');
const db = require('../db/database');

const router = express.Router();

// GET /api/watchlist
router.get('/', (req, res) => {
  const rows = db.prepare('SELECT * FROM watchlist ORDER BY created_at DESC').all();
  res.json({ success: true, watchlist: rows });
});

// POST /api/watchlist { coinId, symbol, name, alertThreshold }
router.post('/', (req, res) => {
  const { coinId, symbol, name, alertThreshold } = req.body || {};
  if (!coinId || !symbol || !name) {
    return res.status(400).json({ success: false, error: 'coinId, symbol and name are required' });
  }
  try {
    db.prepare(
      'INSERT INTO watchlist (coin_id, symbol, name, alert_threshold) VALUES (?, ?, ?, ?)'
    ).run(coinId, symbol.toUpperCase(), name, alertThreshold ?? 75);
    const row = db.prepare('SELECT * FROM watchlist WHERE coin_id = ?').get(coinId);
    res.status(201).json({ success: true, watchlist: row });
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json({ success: false, error: 'Coin already in watchlist' });
    }
    console.error('[route:POST /api/watchlist]', err.message);
    res.status(500).json({ success: false, error: 'Failed to add to watchlist' });
  }
});

// DELETE /api/watchlist/:coinId
router.delete('/:coinId', (req, res) => {
  const info = db.prepare('DELETE FROM watchlist WHERE coin_id = ?').run(req.params.coinId);
  res.json({ success: true, deleted: info.changes });
});

module.exports = router;
