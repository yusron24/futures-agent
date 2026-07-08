const express = require('express');
const db = require('../db/database');

const router = express.Router();

// GET /api/signals?limit=100&coinId=bitcoin
router.get('/', (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  let rows;
  if (req.query.coinId) {
    rows = db
      .prepare('SELECT * FROM signals WHERE coin_id = ? ORDER BY created_at DESC LIMIT ?')
      .all(req.query.coinId, limit);
  } else {
    rows = db.prepare('SELECT * FROM signals ORDER BY created_at DESC LIMIT ?').all(limit);
  }
  res.json({ success: true, signals: rows, count: rows.length });
});

module.exports = router;
