const path = require('path');
const fs = require('fs');

let DatabaseSync;
try {
  // Built into Node.js (no native compilation needed - works on every
  // platform, including Termux/Android where node-gyp builds fail).
  ({ DatabaseSync } = require('node:sqlite'));
} catch (err) {
  console.error(
    'This app requires Node.js >= 22.5 (the built-in `node:sqlite` module). ' +
      'Please upgrade Node.js. On Node 22.5-22.12 you may also need to run with the ' +
      '--experimental-sqlite flag.'
  );
  throw err;
}

const dataDir = path.join(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new DatabaseSync(path.join(dataDir, 'screener.db'));
db.exec('PRAGMA journal_mode = WAL;');

db.exec(`
  CREATE TABLE IF NOT EXISTS watchlist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    coin_id TEXT NOT NULL UNIQUE,
    symbol TEXT NOT NULL,
    name TEXT NOT NULL,
    alert_threshold REAL DEFAULT 75,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    coin_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    name TEXT NOT NULL,
    score REAL NOT NULL,
    price REAL,
    change_24h REAL,
    volume_spike REAL,
    rsi REAL,
    macd_histogram REAL,
    volatility REAL,
    social_score REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_signals_coin_id ON signals(coin_id);
  CREATE INDEX IF NOT EXISTS idx_signals_created_at ON signals(created_at);
`);

module.exports = db;
