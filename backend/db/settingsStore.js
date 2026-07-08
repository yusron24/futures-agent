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
  cryptoquantApiKey: process.env.CRYPTOQUANT_API_KEY || '',
  glassnodeApiKey: process.env.GLASSNODE_API_KEY || '',
  whaleAlertApiKey: process.env.WHALE_ALERT_API_KEY || '',
  scanIntervalMinutes: parseInt(process.env.SCAN_INTERVAL_MINUTES || '5', 10),
  signalScoreThreshold: parseFloat(process.env.SIGNAL_SCORE_THRESHOLD || '75'),
  detailedCoinsLimit: parseInt(process.env.DETAILED_COINS_LIMIT || '30', 10),
  rsiScreenerCoinsLimit: parseInt(process.env.RSI_SCREENER_COINS_LIMIT || '100', 10),
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || '',
  telegramChatId: process.env.TELEGRAM_CHAT_ID || '',
  telegramEnabled: process.env.TELEGRAM_ENABLED === 'true',
  discordWebhookUrl: process.env.DISCORD_WEBHOOK_URL || '',
  discordEnabled: process.env.DISCORD_ENABLED === 'true',
  frontendUrl: process.env.FRONTEND_URL || 'http://localhost:5173',
};

const NUMERIC_KEYS = new Set(['scanIntervalMinutes', 'signalScoreThreshold', 'detailedCoinsLimit', 'rsiScreenerCoinsLimit']);
const BOOLEAN_KEYS = new Set(['telegramEnabled', 'discordEnabled']);

const LIMITS = {
  scanIntervalMinutes: { min: 1, max: 120 },
  signalScoreThreshold: { min: 0, max: 100 },
  detailedCoinsLimit: { min: 5, max: 250 },
  rsiScreenerCoinsLimit: { min: 10, max: 250 },
};

function coerce(key, rawValue) {
  if (NUMERIC_KEYS.has(key)) return Number(rawValue);
  if (BOOLEAN_KEYS.has(key)) return rawValue === 'true' || rawValue === true;
  return rawValue;
}

function getSettings() {
  const rows = db.prepare('SELECT key, value FROM settings').all();
  const overrides = {};
  for (const row of rows) {
    if (!(row.key in DEFAULTS)) continue;
    overrides[row.key] = coerce(row.key, row.value);
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
      const stored = BOOLEAN_KEYS.has(key) ? String(Boolean(value)) : String(value);
      upsert.run(key, stored);
    }
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }

  return getSettings();
}

module.exports = { getSettings, updateSettings, DEFAULTS };
