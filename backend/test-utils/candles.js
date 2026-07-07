function makeCandle({ open, high, low, close, volume }) {
  // Mirrors the Binance kline array shape: [openTime, open, high, low, close, volume, ...]
  return [0, String(open), String(high), String(low), String(close), String(volume), 0];
}

// Builds `count` baseline candles (flat, non-triggering) and applies overrides
// at specific indices, e.g. { 499: {...}, 498: {...} }.
function buildCandles(count, overrides = {}) {
  const candles = [];
  for (let i = 0; i < count; i++) {
    candles.push(makeCandle({ open: 100, high: 101, low: 99, close: 100.5, volume: 10 }));
  }
  Object.entries(overrides).forEach(([idx, candle]) => {
    candles[Number(idx)] = makeCandle(candle);
  });
  return candles;
}

module.exports = { makeCandle, buildCandles };
