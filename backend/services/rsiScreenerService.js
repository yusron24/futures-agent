const { getLatestScreening } = require('./screeningService');

/**
 * Coins currently oversold (RSI<30) / overbought (RSI>70), read straight
 * from the latest full screening cycle. Binance's generous rate limit
 * means the main screening pipeline already computes RSI for the entire
 * universe every cycle, so this no longer needs its own independent
 * background rotation the way the old CoinGecko-backed version did.
 */
function getRsiScreenerResults() {
  const latest = getLatestScreening();
  const scanned = latest.coins.filter((c) => c.rsi != null);
  const oversold = scanned.filter((c) => c.rsi < 30).sort((a, b) => a.rsi - b.rsi);
  const overbought = scanned.filter((c) => c.rsi > 70).sort((a, b) => b.rsi - a.rsi);

  return {
    updatedAt: latest.updatedAt,
    poolSize: latest.coins.length,
    scannedCount: scanned.length,
    oversold,
    overbought,
  };
}

module.exports = { getRsiScreenerResults };
