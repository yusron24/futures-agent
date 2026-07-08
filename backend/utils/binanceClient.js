const axios = require('axios');
const { HttpsProxyAgent } = require('https-proxy-agent');
const { getSettings } = require('../db/settingsStore');

const BASE_URL = process.env.BINANCE_FUTURES_API_URL || 'https://fapi.binance.com';

const client = axios.create({ baseURL: BASE_URL, timeout: 15000 });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------
// Optional outbound proxy - useful when Binance rate-limits or blocks
// the server's IP (common on shared/mobile/datacenter IPs). Configured
// via Settings (proxyUrl/proxyEnabled), format: http://user:pass@host:port.
// The agent is rebuilt only when the URL actually changes, so normal
// requests don't pay agent-construction cost every call.
// ---------------------------------------------------------------------
let cachedAgent = null;
let cachedProxyUrl = null;

function getProxyAgent() {
  const { proxyEnabled, proxyUrl } = getSettings();
  if (!proxyEnabled || !proxyUrl) return null;

  if (proxyUrl !== cachedProxyUrl) {
    try {
      cachedAgent = new HttpsProxyAgent(proxyUrl);
      cachedProxyUrl = proxyUrl;
    } catch (err) {
      console.error(`[binance] invalid proxy URL, ignoring: ${err.message}`);
      cachedAgent = null;
      cachedProxyUrl = null;
    }
  }
  return cachedAgent;
}

// ---------------------------------------------------------------------
// Binance's public market-data endpoints (klines, ticker, exchangeInfo)
// need no API key and have a generous weight budget (2400/min for the
// futures API), so pacing here is a politeness/safety margin rather than
// a hard requirement - unlike CoinGecko's free tier this app used to hit
// constantly. Still adapts on 429 (rate limit) / 418 (IP auto-ban) just
// in case, same pattern as before but starting much faster and capping
// much lower.
// ---------------------------------------------------------------------
const MIN_INTERVAL_MS = 60;
const MAX_INTERVAL_MS = 5000;
let currentIntervalMs = parseInt(process.env.BINANCE_FETCH_DELAY_MS || '120', 10);
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
  currentIntervalMs = Math.min(MAX_INTERVAL_MS, Math.round(currentIntervalMs * 2));
  consecutiveSuccesses = 0;
  if (currentIntervalMs !== before) {
    console.warn(`[binance] backing off pacing to ${currentIntervalMs}ms between requests`);
  }
}

function reportSuccess() {
  consecutiveSuccesses += 1;
  if (consecutiveSuccesses >= 15 && currentIntervalMs > MIN_INTERVAL_MS) {
    currentIntervalMs = Math.max(MIN_INTERVAL_MS, Math.round(currentIntervalMs * 0.8));
    consecutiveSuccesses = 0;
  }
}

/**
 * GET with retry/backoff for Binance rate limiting (429/418) and
 * transient network errors, paced through a shared adaptive limiter and
 * routed through the configured proxy (if any).
 */
async function getWithRetry(url, config = {}, retries = 3) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await waitForSlot();
    try {
      const agent = getProxyAgent();
      const requestConfig = agent ? { ...config, httpsAgent: agent, proxy: false } : config;
      const res = await client.get(url, requestConfig);
      reportSuccess();
      return res.data;
    } catch (err) {
      const status = err.response?.status;
      const isRateLimited = status === 429 || status === 418;
      const isRetryable = isRateLimited || !err.response || status >= 500;
      if (isRateLimited) reportRateLimited();

      if (!isRetryable || attempt >= retries) {
        console.error(`[binance] GET ${url} failed: ${err.message}${status ? ` (status ${status})` : ''}`);
        throw err;
      }

      const backoffMs = 1000 * 2 ** attempt;
      console.warn(`[binance] GET ${url} -> ${status || 'network error'}, retrying in ${backoffMs}ms (attempt ${attempt + 1}/${retries})`);
      await sleep(backoffMs);
      attempt += 1;
    }
  }
}

module.exports = { client, getWithRetry, sleep };
