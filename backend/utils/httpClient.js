const axios = require('axios');
const { getSettings } = require('../db/settingsStore');

const BASE_URL = process.env.COINGECKO_API_URL || 'https://api.coingecko.com/api/v3';

const client = axios.create({ baseURL: BASE_URL, timeout: 15000 });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------
// Shared, adaptive rate limiter used by *every* CoinGecko call the app
// makes (main screening cycle, RSI screener rotation, on-demand coin
// detail, categories, ...). CoinGecko's real free-tier limit in practice
// varies a lot by IP/network (observed anywhere from ~5 to ~15 req/min,
// sometimes stricter on mobile/shared IPs) - rather than guessing one
// fixed delay, every request reserves a slot on a shared clock that
// slows down automatically on 429s and gradually speeds back up after a
// run of clean successes. This also means two independent features
// (screening + RSI screener) never accidentally burst the API at the
// same time even if their own pacing logic didn't coordinate.
// ---------------------------------------------------------------------
const MIN_INTERVAL_MS = 2000;
const MAX_INTERVAL_MS = 20000;
let currentIntervalMs = parseInt(process.env.DETAILED_FETCH_DELAY_MS || '4000', 10);
let nextAllowedAt = 0;
let consecutiveSuccesses = 0;

async function waitForSlot() {
  const now = Date.now();
  const waitMs = Math.max(0, nextAllowedAt - now);
  nextAllowedAt = Math.max(now, nextAllowedAt) + currentIntervalMs;
  if (waitMs > 0) await sleep(waitMs);
}

function reportRateLimited() {
  const before = currentIntervalMs;
  currentIntervalMs = Math.min(MAX_INTERVAL_MS, Math.round(currentIntervalMs * 1.6));
  consecutiveSuccesses = 0;
  if (currentIntervalMs !== before) {
    console.warn(`[coingecko] backing off pacing to ${currentIntervalMs}ms between requests`);
  }
}

function reportSuccess() {
  consecutiveSuccesses += 1;
  if (consecutiveSuccesses >= 8 && currentIntervalMs > MIN_INTERVAL_MS) {
    currentIntervalMs = Math.max(MIN_INTERVAL_MS, Math.round(currentIntervalMs * 0.85));
    consecutiveSuccesses = 0;
  }
}

/**
 * GET with retry/backoff for CoinGecko rate limiting (HTTP 429) and
 * transient network errors. Backs off exponentially per-request (2s, 4s,
 * 8s...) and also paces every request through the shared adaptive
 * limiter above. The API key is read fresh from settingsStore on every
 * call so changes made on the Settings page take effect immediately, no
 * restart needed.
 */
async function getWithRetry(url, config = {}, retries = 3) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await waitForSlot();
    try {
      const { coingeckoApiKey } = getSettings();
      const headers = {
        ...(config.headers || {}),
        ...(coingeckoApiKey ? { 'x-cg-demo-api-key': coingeckoApiKey } : {}),
      };
      const res = await client.get(url, { ...config, headers });
      reportSuccess();
      return res.data;
    } catch (err) {
      const status = err.response?.status;
      const isRateLimited = status === 429;
      const isRetryable = isRateLimited || !err.response || status >= 500;
      if (isRateLimited) reportRateLimited();

      if (!isRetryable || attempt >= retries) {
        console.error(`[coingecko] GET ${url} failed: ${err.message}${status ? ` (status ${status})` : ''}`);
        throw err;
      }

      const backoffMs = 2000 * 2 ** attempt;
      console.warn(`[coingecko] GET ${url} -> ${status || 'network error'}, retrying in ${backoffMs}ms (attempt ${attempt + 1}/${retries})`);
      await sleep(backoffMs);
      attempt += 1;
    }
  }
}

module.exports = { client, getWithRetry, sleep };
