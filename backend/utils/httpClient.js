const axios = require('axios');
const { getSettings } = require('../db/settingsStore');

const BASE_URL = process.env.COINGECKO_API_URL || 'https://api.coingecko.com/api/v3';

const client = axios.create({ baseURL: BASE_URL, timeout: 15000 });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * GET with retry/backoff for CoinGecko rate limiting (HTTP 429) and
 * transient network errors. Backs off exponentially: 2s, 4s, 8s...
 * The API key is read fresh from settingsStore on every call so changes
 * made on the Settings page take effect immediately, no restart needed.
 */
async function getWithRetry(url, config = {}, retries = 3) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const { coingeckoApiKey } = getSettings();
      const headers = {
        ...(config.headers || {}),
        ...(coingeckoApiKey ? { 'x-cg-demo-api-key': coingeckoApiKey } : {}),
      };
      const res = await client.get(url, { ...config, headers });
      return res.data;
    } catch (err) {
      const status = err.response?.status;
      const isRateLimited = status === 429;
      const isRetryable = isRateLimited || !err.response || status >= 500;

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
