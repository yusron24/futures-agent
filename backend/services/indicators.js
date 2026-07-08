/**
 * Lightweight technical indicator utilities. No external TA library -
 * implemented from scratch on plain arrays of closing prices.
 */

function sma(values, period) {
  if (values.length < period) return null;
  const slice = values.slice(values.length - period);
  return slice.reduce((a, b) => a + b, 0) / period;
}

/** Full EMA series (same length as input, first `period-1` entries seeded via SMA). */
function emaSeries(values, period) {
  if (values.length < period) return [];
  const k = 2 / (period + 1);
  const result = [];
  const seed = values.slice(0, period).reduce((a, b) => a + b, 0) / period;
  result[period - 1] = seed;
  for (let i = period; i < values.length; i += 1) {
    result[i] = values[i] * k + result[i - 1] * (1 - k);
  }
  return result;
}

/**
 * Relative Strength Index (Wilder's smoothing), standard 14-period.
 * Returns a number 0-100, or null if not enough data.
 */
function calculateRSI(closes, period = 14) {
  if (closes.length < period + 1) return null;

  let gains = 0;
  let losses = 0;
  for (let i = 1; i <= period; i += 1) {
    const diff = closes[i] - closes[i - 1];
    if (diff >= 0) gains += diff;
    else losses -= diff;
  }
  let avgGain = gains / period;
  let avgLoss = losses / period;

  for (let i = period + 1; i < closes.length; i += 1) {
    const diff = closes[i] - closes[i - 1];
    const gain = diff > 0 ? diff : 0;
    const loss = diff < 0 ? -diff : 0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
  }

  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

/**
 * MACD (12,26,9). Returns { macd, signal, histogram } using the latest
 * values, or null if there isn't enough history for the slow EMA.
 */
function calculateMACD(closes, fastPeriod = 12, slowPeriod = 26, signalPeriod = 9) {
  if (closes.length < slowPeriod + signalPeriod) return null;

  const fastEma = emaSeries(closes, fastPeriod);
  const slowEma = emaSeries(closes, slowPeriod);

  const macdLine = [];
  for (let i = 0; i < closes.length; i += 1) {
    if (fastEma[i] !== undefined && slowEma[i] !== undefined) {
      macdLine[i] = fastEma[i] - slowEma[i];
    }
  }

  const macdValues = macdLine.filter((v) => v !== undefined);
  const signalSeries = emaSeries(macdValues, signalPeriod);
  const signal = signalSeries[signalSeries.length - 1];
  const macd = macdValues[macdValues.length - 1];

  if (macd === undefined || signal === undefined) return null;
  return { macd, signal, histogram: macd - signal };
}

/** Volatility as % spread of high-low relative to the average price. */
function calculateVolatility(high, low, avgPrice) {
  if (!avgPrice) return 0;
  return ((high - low) / avgPrice) * 100;
}

/** Downsample [timestamp, value] pairs from CoinGecko market_chart to one point per UTC day. */
function toDailySeries(pairs) {
  const byDay = new Map();
  for (const [ts, value] of pairs) {
    const day = new Date(ts).toISOString().slice(0, 10);
    byDay.set(day, value); // keep the last value seen for that day
  }
  return Array.from(byDay.entries())
    .sort((a, b) => (a[0] < b[0] ? -1 : 1))
    .map(([, value]) => value);
}

module.exports = { sma, emaSeries, calculateRSI, calculateMACD, calculateVolatility, toDailySeries };
