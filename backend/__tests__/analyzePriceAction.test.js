const { analyzePriceAction } = require('../server');
const { buildCandles } = require('../test-utils/candles');

describe('analyzePriceAction', () => {
  test('returns null when there are fewer than 500 candles', () => {
    expect(analyzePriceAction(buildCandles(10))).toBeNull();
  });

  test('returns null when candles is null/undefined', () => {
    expect(analyzePriceAction(null)).toBeNull();
    expect(analyzePriceAction(undefined)).toBeNull();
  });

  test('detects a Bullish Engulfing candle', () => {
    const candles = buildCandles(500, {
      499: { open: 102, high: 110.5, low: 101.5, close: 110, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Bullish Engulfing');
  });

  test('detects a Bearish Engulfing candle', () => {
    const candles = buildCandles(500, {
      499: { open: 99, high: 99.5, low: 89.5, close: 90, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Bearish Engulfing');
  });

  test('detects a Hammer candle', () => {
    const candles = buildCandles(500, {
      499: { open: 100, high: 101.3, low: 90, close: 101, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Hammer');
  });

  test('detects a Shooting Star candle', () => {
    const candles = buildCandles(500, {
      499: { open: 101, high: 112, low: 99.7, close: 100, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Shooting Star');
  });

  test('detects a Doji candle', () => {
    const candles = buildCandles(500, {
      499: { open: 100, high: 105, low: 95, close: 100.05, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Doji Bullish');
  });

  test('detects a Marubozu candle', () => {
    const candles = buildCandles(500, {
      499: { open: 100, high: 110.2, low: 99.8, close: 110, volume: 10 },
    });
    const result = analyzePriceAction(candles);
    expect(result.patterns).toContain('Marubozu Bullish');
  });

  test('computes support, resistance and volume ratio across the full window', () => {
    const candles = buildCandles(500, {
      250: { open: 100, high: 500, low: 10, close: 100, volume: 10 },
      499: { open: 100, high: 101, low: 99, close: 100.5, volume: 50 },
    });
    const result = analyzePriceAction(candles);
    expect(result.resistance).toBe(500);
    expect(result.support).toBe(10);
    // avgVolume of the last 20 candles = (19*10 + 50) / 20 = 12
    expect(result.volRatio).toBeCloseTo(50 / 12, 4);
  });
});
