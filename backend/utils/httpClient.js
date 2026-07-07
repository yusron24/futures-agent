const axios = require('axios');

const BASE_URL = process.env.COINGECKO_API_URL || 'https://api.coingecko.com/api/v3';
const API_KEY = process.env.COINGECKO_API_KEY || '';

const client = axios.create({
  baseURL: BASE_URL,
  timeout: 15000,
  headers: API_KEY ? { 'x-cg-demo-api-key': API_KEY } : {},
});

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * GET with retry/backoff for CoinGecko rate limiting (HTTP 429) and
 * transient network errors. Backs off exponentially: 2s, 4s, 8s...
 */
async function getWithRetry(url, config = {}, retries = 3) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const res = await client.get(url, config);
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
