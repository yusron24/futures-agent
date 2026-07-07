const db = require('./database');

db.exec(`
  CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
  );
`);

// .env values are the initial defaults; anything saved via the Settings
// page is persisted here in SQLite and takes precedence from then on
// (survives restarts, no need to touch .env or restart the process).
const DEFAULTS = {
  coingeckoApiKey: process.env.COINGECKO_API_KEY || '',
  lunarcrushApiKey: process.env.LUNARCRUSH_API_KEY || process.env.SOCIAL_API_KEY || '',
  scanIntervalMinutes: parseInt(process.env.SCAN_INTERVAL_MINUTES || '5', 10),
  signalScoreThreshold: parseFloat(process.env.SIGNAL_SCORE_THRESHOLD || '75'),
  detailedCoinsLimit: parseInt(process.env.DETAILED_COINS_LIMIT || '60', 10),
};

const NUMERIC_KEYS = new Set(['scanIntervalMinutes', 'signalScoreThreshold', 'detailedCoinsLimit']);

const LIMITS = {
  scanIntervalMinutes: { min: 1, max: 120 },
  signalScoreThreshold: { min: 0, max: 100 },
  detailedCoinsLimit: { min: 5, max: 250 },
};

function getSettings() {
  const rows = db.prepare('SELECT key, value FROM settings').all();
  const overrides = {};
  for (const row of rows) {
    if (!(row.key in DEFAULTS)) continue;
    overrides[row.key] = NUMERIC_KEYS.has(row.key) ? Number(row.value) : row.value;
  }
  return { ...DEFAULTS, ...overrides };
}

/** Validates & persists a partial settings update, returns the merged settings. */
function updateSettings(partial) {
  const upsert = db.prepare(
    'INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value'
  );

  const entries = Object.entries(partial).filter(([key]) => key in DEFAULTS);

  for (const [key, value] of entries) {
    if (NUMERIC_KEYS.has(key)) {
      const num = Number(value);
      if (Number.isNaN(num)) throw new Error(`${key} must be a number`);
      const { min, max } = LIMITS[key];
      if (num < min || num > max) throw new Error(`${key} must be between ${min} and ${max}`);
    }
  }

  db.exec('BEGIN');
  try {
    for (const [key, value] of entries) {
      upsert.run(key, String(value));
    }
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }

  return getSettings();
}

module.exports = { getSettings, updateSettings, DEFAULTS };
