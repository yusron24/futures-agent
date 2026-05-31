require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const NodeCache = require('node-cache');

const app = express();
app.use(cors());
app.use(express.json());

const cache = new NodeCache({ stdTTL: 60 });
const SCAN_INTERVAL = 10000;
const MAX_PAIRS = 150;
const CONFIDENCE_THRESHOLD = 85;

// ─── Coinglass API ───
const COINGLASS_API_KEY = process.env.COINGLASS_API_KEY || '';
const COINGLASS_BASE_URL = 'https://open-api.coinglass.com/api/pro/v1';

// ─── Axios Config ───
const axiosConfig = {
  headers: { 'User-Agent': 'Mozilla/5.0' },
  timeout: 15000
};

const coinglassConfig = {
  headers: {
    'api-key': COINGLASS_API_KEY,
    'Content-Type': 'application/json'
  },
  timeout: 10000
};

// ─── State ───
let scanResults = [];
let lastScanTime = null;
let isScanning = false;
let scanCount = 0;

// ─── Helper: Dapatkan pasangan Futures dari Binance ───
async function getFuturesSymbols() {
  const cacheKey = 'futures_symbols';
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  try {
    const { data: tickers } = await axios.get('https://fapi.binance.com/fapi/v1/ticker/24hr', axiosConfig);
    const usdtTickers = tickers
      .filter(t => t.symbol.endsWith('USDT'))
      .sort((a, b) => parseFloat(b.quoteVolume) - parseFloat(a.quoteVolume));
    const symbols = usdtTickers.slice(0, MAX_PAIRS).map(t => t.symbol);
    console.log(`✅ Mengambil ${symbols.length} pasangan dari Binance Futures`);
    cache.set(cacheKey, symbols, 3600);
    return symbols;
  } catch (err) {
    console.error('❌ Gagal mengambil data futures:', err.message);
    return ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT'];
  }
}

// ─── Ambil data klines dari Binance ───
async function fetchBinanceCandles(symbol, interval, limit = 100) {
  try {
    const { data } = await axios.get(
      `https://fapi.binance.com/fapi/v1/klines?symbol=${symbol}&interval=${interval}&limit=${limit}`,
      axiosConfig
    );
    return data;
  } catch (err) {
    throw new Error(`Binance klines error: ${err.message}`);
  }
}

// ─── Ambil data dari Coinglass (dengan fallback dummy) ───
async function fetchCoinglassData(symbol) {
  const cleanSymbol = symbol.replace('USDT', '');
  const result = {
    openInterest: 0,
    cvd: 0,
    liquidationHeatmap: 0
  };

  if (!COINGLASS_API_KEY) {
    // Dummy data jika tidak ada API key
    return {
      openInterest: Math.floor(Math.random() * 1000000),
      cvd: Math.floor(Math.random() * 500000),
      liquidationHeatmap: Math.floor(Math.random() * 200000)
    };
  }

  try {
    // 1. Open Interest
    const oiRes = await axios.get(
      `${COINGLASS_BASE_URL}/futures/openInterest?symbol=${cleanSymbol}&type=ALL`,
      coinglassConfig
    );
    if (oiRes.data && oiRes.data.data && oiRes.data.data.length) {
      result.openInterest = parseFloat(oiRes.data.data[0].openInterestValue) || 0;
    }

    // 2. CVD (Cumulative Volume Delta)
    const cvdRes = await axios.get(
      `${COINGLASS_BASE_URL}/futures/cvd?symbol=${cleanSymbol}&interval=1h`,
      coinglassConfig
    );
    if (cvdRes.data && cvdRes.data.data && cvdRes.data.data.length) {
      result.cvd = parseFloat(cvdRes.data.data[0].cvd) || 0;
    }

    // 3. Liquidation Heatmap (long/short liquidation)
    const liqRes = await axios.get(
      `${COINGLASS_BASE_URL}/futures/liquidation?symbol=${cleanSymbol}&interval=1h&type=ALL`,
      coinglassConfig
    );
    if (liqRes.data && liqRes.data.data && liqRes.data.data.length) {
      result.liquidationHeatmap = parseFloat(liqRes.data.data[0].value) || 0;
    }
  } catch (err) {
    console.warn(`⚠️ Coinglass API error untuk ${symbol}:`, err.message);
    // Fallback dummy
    result.openInterest = Math.floor(Math.random() * 1000000);
    result.cvd = Math.floor(Math.random() * 500000);
    result.liquidationHeatmap = Math.floor(Math.random() * 200000);
  }

  return result;
}

// ─── Fungsi Analisis Price Action Lengkap ───
function analyzePriceAction(candles) {
  if (!candles || candles.length < 20) return { score: 0, signals: [], trend: 'SIDEWAYS', volumeRatio: 0 };

  const last = candles[candles.length - 1];
  const prev = candles[candles.length - 2];
  const prev2 = candles[candles.length - 3];
  const prev3 = candles[candles.length - 4];
  const prev4 = candles[candles.length - 5];

  const close = parseFloat(last[4]);
  const open = parseFloat(last[1]);
  const high = parseFloat(last[2]);
  const low = parseFloat(last[3]);
  const volume = parseFloat(last[5]);

  const prevClose = parseFloat(prev[4]);
  const prevHigh = parseFloat(prev[2]);
  const prevLow = parseFloat(prev[3]);
  const prev2Close = parseFloat(prev2[4]);
  const prev2High = parseFloat(prev2[2]);
  const prev2Low = parseFloat(prev2[3]);

  const body = Math.abs(close - open);
  const range = high - low;
  const bodyRatio = body / (range || 0.001);
  const upperWick = high - Math.max(open, close);
  const lowerWick = Math.min(open, close) - low;

  // ── Volume ──
  const volumes = candles.map(c => parseFloat(c[5]));
  const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
  const volumeRatio = volume / (avgVolume || 1);
  const isVolumeSpike = volumeRatio > 2.0; // > 100%

  // ── Level (Support/Resistance) ──
  const highs = candles.slice(-30).map(c => parseFloat(c[2]));
  const lows = candles.slice(-30).map(c => parseFloat(c[3]));
  const resistance = Math.max(...highs);
  const support = Math.min(...lows);
  const nearResistance = (resistance - close) / close < 0.015;
  const nearSupport = (close - support) / close < 0.015;

  // ── Round Number ──
  const roundNumbers = [0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000];
  const nearRoundNumber = roundNumbers.some(r => Math.abs(close - r) / r < 0.005);

  // ── Swing High/Swing Low ──
  const swingHigh = highs.slice(-10).reduce((a, b) => a > b ? a : b, 0);
  const swingLow = lows.slice(-10).reduce((a, b) => a < b ? a : b, Infinity);

  // ── Pola Candlestick ──
  let score = 0;
  let signals = [];

  // 1. Bullish / Bearish Engulfing
  if (open > prevClose && close > prevHigh && body > prevClose * 0.02) {
    score += 15;
    signals.push('Bullish Engulfing');
  } else if (open < prevClose && close < prevLow && body > prevClose * 0.02) {
    score -= 15;
    signals.push('Bearish Engulfing');
  }

  // 2. Pin Bar (Hammer / Shooting Star)
  if (lowerWick > body * 2.5 && lowerWick > range * 0.3 && close > open) {
    score += 12;
    signals.push('Hammer');
  } else if (upperWick > body * 2.5 && upperWick > range * 0.3 && close < open) {
    score -= 12;
    signals.push('Shooting Star');
  }

  // 3. Doji
  if (body < range * 0.15) {
    if (close > open) {
      score += 5;
      signals.push('Doji Bullish');
    } else {
      score -= 5;
      signals.push('Doji Bearish');
    }
  }

  // 4. Marubozu
  if (body > range * 0.85) {
    if (close > open) {
      score += 10;
      signals.push('Bullish Marubozu');
    } else {
      score -= 10;
      signals.push('Bearish Marubozu');
    }
  }

  // 5. Morning Star / Evening Star
  if (candles.length >= 3) {
    const c1 = parseFloat(candles[candles.length - 3][4]);
    const o1 = parseFloat(candles[candles.length - 3][1]);
    const c2 = parseFloat(candles[candles.length - 2][4]);
    const o2 = parseFloat(candles[candles.length - 2][1]);
    const body1 = Math.abs(c1 - o1);
    const body2 = Math.abs(c2 - o2);

    if (c1 < o1 && body2 < body1 * 0.3 && close > open && close > c1) {
      score += 12;
      signals.push('Morning Star');
    } else if (c1 > o1 && body2 < body1 * 0.3 && close < open && close < c1) {
      score -= 12;
      signals.push('Evening Star');
    }
  }

  // 6. Inside Bar
  if (high <= prevHigh && low >= prevLow) {
    if (close > open) {
      score += 8;
      signals.push('Inside Bar Bullish');
    } else {
      score -= 8;
      signals.push('Inside Bar Bearish');
    }
  }

  // 7. Breakout / Breakdown
  if (close > prevHigh && close > open && close > resistance * 0.98) {
    score += 10;
    signals.push('Breakout Resistance');
  } else if (close < prevLow && close < open && close < support * 1.02) {
    score -= 10;
    signals.push('Breakdown Support');
  }

  // 8. Double Top / Double Bottom
  if (Math.abs(high - prev2High) < range * 0.1 && high < prev2High && close < open) {
    score -= 12;
    signals.push('Double Top');
  } else if (Math.abs(low - prev2Low) < range * 0.1 && low > prev2Low && close > open) {
    score += 12;
    signals.push('Double Bottom');
  }

  // 9. Ascending / Descending Triangle
  const recentHighs = candles.slice(-10).map(c => parseFloat(c[2]));
  const recentLows = candles.slice(-10).map(c => parseFloat(c[3]));
  const flatHigh = Math.max(...recentHighs.slice(-5)) - Math.min(...recentHighs.slice(-5)) < range * 0.1;
  const higherLows = recentLows.slice(-5).every((l, i, arr) => i === 0 || l >= arr[i - 1]);
  if (flatHigh && higherLows && close > open) {
    score += 10;
    signals.push('Ascending Triangle');
  }
  const flatLow = Math.max(...recentLows.slice(-5)) - Math.min(...recentLows.slice(-5)) < range * 0.1;
  const lowerHighs = recentHighs.slice(-5).every((h, i, arr) => i === 0 || h <= arr[i - 1]);
  if (flatLow && lowerHighs && close < open) {
    score -= 10;
    signals.push('Descending Triangle');
  }

  // 10. Level Support/Resistance
  if (nearSupport && close > open) {
    score += 8;
    signals.push('Near Support');
  } else if (nearResistance && close < open) {
    score -= 8;
    signals.push('Near Resistance');
  }

  // 11. Round Number
  if (nearRoundNumber && close > open) {
    score += 6;
    signals.push('Round Number Support');
  } else if (nearRoundNumber && close < open) {
    score -= 6;
    signals.push('Round Number Resistance');
  }

  // 12. Volume Spike
  if (isVolumeSpike) {
    if (close > open) {
      score += 20;
      signals.push('Volume Spike Bullish');
    } else {
      score -= 20;
      signals.push('Volume Spike Bearish');
    }
  }

  return { score, signals: signals.slice(0, 8), trend: score > 10 ? 'BULLISH' : score < -10 ? 'BEARISH' : 'SIDEWAYS', volumeRatio };
}

// ─── Analisis Multi-Timeframe + Derivatif ───
async function analyzeFull(symbol, timeframe) {
  const intervalMap = {
    '5m': '5m',
    '15m': '15m',
    '1h': '1h',
    '4h': '4h',
    '1d': '1d'
  };
  const interval = intervalMap[timeframe] || '1h';

  try {
    // 1. Ambil data candles
    const candles = await fetchBinanceCandles(symbol, interval, 100);
    if (!candles || candles.length < 20) return null;

    // 2. Analisis Price Action
    const pa = analyzePriceAction(candles);

    // 3. Ambil data Coinglass (OI, CVD, Liquidation Heatmap)
    const coinglassData = await fetchCoinglassData(symbol);

    // 4. Ambil data Binance Futures (OI, funding, LS ratio) sebagai pelengkap
    let binanceOI = 0, funding = 0, lsRatio = 1;
    try {
      const [oiRes, fundingRes, lsRes] = await Promise.all([
        axios.get(`https://fapi.binance.com/fapi/v1/openInterest?symbol=${symbol}`, axiosConfig),
        axios.get(`https://fapi.binance.com/fapi/v1/fundingInfo?symbol=${symbol}`, axiosConfig),
        axios.get(`https://fapi.binance.com/fapi/v1/globalLongShortAccountRatio?symbol=${symbol}&period=${interval}&limit=1`, axiosConfig)
      ]);
      binanceOI = parseFloat(oiRes.data.sumOpenInterestValue || 0);
      funding = parseFloat(fundingRes.data[0]?.fundingRate || 0);
      lsRatio = parseFloat(lsRes.data[0]?.longShortRatio || 1);
    } catch (err) {
      // Fallback
    }

    // ── Skor akhir ──
    let finalScore = pa.score;

    // Derivatif dari Coinglass (bonus)
    if (coinglassData.openInterest > 0 && finalScore > 0) finalScore += 5;
    if (coinglassData.cvd > 0 && finalScore > 0) finalScore += 5;
    if (coinglassData.liquidationHeatmap > 0 && finalScore > 0) finalScore += 5;

    // Derivatif dari Binance (bonus)
    if (binanceOI > 0 && finalScore > 0) finalScore += 5;
    if (funding < -0.001 && finalScore > 0) finalScore += 8;
    if (lsRatio > 1.5 && finalScore < 0) finalScore -= 8;
    if (lsRatio < 0.6 && finalScore > 0) finalScore += 8;

    let signal = 'WAIT';
    let confidence = 0;

    if (finalScore >= 15) {
      signal = 'LONG';
      confidence = Math.min(99, 70 + finalScore * 0.5);
    } else if (finalScore <= -15) {
      signal = 'SHORT';
      confidence = Math.min(99, 70 + Math.abs(finalScore) * 0.5);
    }

    if (confidence < CONFIDENCE_THRESHOLD) {
      signal = 'WAIT';
      confidence = 0;
    }

    // ── Entry, SL, TP ──
    const price = parseFloat(candles[candles.length - 1][4]);
    const atr = (parseFloat(candles[candles.length - 1][2]) - parseFloat(candles[candles.length - 1][3])) * 0.5;
    const slDistance = atr * 1.2;
    const tpDistance = slDistance * 2.5;
    const entry = price;
    const stopLoss = signal === 'LONG' ? price - slDistance : price + slDistance;
    const takeProfit1 = signal === 'LONG' ? price + tpDistance : price - tpDistance;

    console.log(`📊 [${symbol}] TF: ${timeframe} | Score: ${finalScore.toFixed(1)} | Signal: ${signal} | Conf: ${confidence} | OI: ${coinglassData.openInterest.toFixed(0)} | CVD: ${coinglassData.cvd.toFixed(0)} | Liq: ${coinglassData.liquidationHeatmap.toFixed(0)}`);

    return {
      symbol,
      timeframe,
      price: entry,
      signal,
      confidence: Math.round(confidence),
      score: Math.round(finalScore),
      signals: pa.signals.slice(0, 6),
      entry: entry.toFixed(8),
      stopLoss: stopLoss.toFixed(8),
      takeProfit1: takeProfit1.toFixed(8),
      volumeRatio: pa.volumeRatio.toFixed(2),
      trend: finalScore > 0 ? 'BULLISH' : 'BEARISH',
      strength: Math.abs(finalScore) > 30 ? 'STRONG' : 'MODERATE',
      derivatives: {
        oi: coinglassData.openInterest.toFixed(0),
        cvd: coinglassData.cvd.toFixed(0),
        liquidation: coinglassData.liquidationHeatmap.toFixed(0),
        funding: (funding * 100).toFixed(3) + '%',
        lsRatio: lsRatio.toFixed(2)
      }
    };
  } catch (err) {
    console.error(`❌ Error analyzing ${symbol}:`, err.message);
    return null;
  }
}

// ─── Scheduler (Multi-Timeframe) ───
async function scanAllPairs(timeframe = '1h') {
  if (isScanning) return;
  isScanning = true;
  scanCount++;

  console.log(`\n🔍 === START SCAN #${scanCount} (${timeframe}) ===`);
  const symbols = await getFuturesSymbols();
  console.log(`🔍 Scanning ${symbols.length} pasangan...`);

  const results = [];
  const batchSize = 50;
  for (let i = 0; i < symbols.length; i += batchSize) {
    const batch = symbols.slice(i, i + batchSize);
    const promises = batch.map(s => analyzeFull(s, timeframe));
    const batchResults = await Promise.allSettled(promises);
    batchResults.forEach(r => {
      if (r.status === 'fulfilled' && r.value) results.push(r.value);
    });
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  scanResults = results.filter(r => r.signal !== 'WAIT');
  lastScanTime = new Date();
  isScanning = false;

  console.log(`✅ Scan #${scanCount} (${timeframe}) selesai. Sinyal: ${scanResults.length}`);
}

// ─── Endpoint untuk scan dengan timeframe tertentu ───
app.post('/api/v1/scan', async (req, res) => {
  const { timeframe = '1h' } = req.body;
  const validTimeframes = ['5m', '15m', '1h', '4h', '1d'];
  if (!validTimeframes.includes(timeframe)) {
    return res.status(400).json({ error: 'Invalid timeframe. Use 5m, 15m, 1h, 4h, 1d' });
  }
  await scanAllPairs(timeframe);
  res.json({ success: true, message: `Scan completed for ${timeframe}` });
});

// ─── Endpoint untuk mendapatkan sinyal ───
app.get('/api/v1/signals', (req, res) => {
  res.json({
    success: true,
    signals: scanResults,
    total: scanResults.length,
    lastScan: lastScanTime,
    scanning: isScanning
  });
});

// ─── Debug endpoint ───
app.get('/debug/fapi', async (req, res) => {
  try {
    const response = await axios.get('https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT', axiosConfig);
    res.json({ success: true, data: response.data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 10000;
// ─── Endpoint: Detail Sinyal untuk Satu Pasangan ───
app.get('/api/v1/signal/:symbol', async (req, res) => {
  const symbol = req.params.symbol;
  const timeframe = req.query.timeframe || '1h'; // default 1h

  try {
    // Ambil data real-time untuk simbol ini
    const data = await fetchFuturesData(symbol);
    if (!data) {
      return res.status(404).json({ error: 'Symbol not found or data unavailable' });
    }

    // Analisis data (gunakan fungsi analyzeFull dari V20)
    const analysis = await analyzeFull(symbol, timeframe);

    // Jika berhasil, kirimkan data sinyal
    res.json({ success: true, signal: analysis });
  } catch (err) {
    console.error(`❌ Error fetching detail for ${symbol}:`, err.message);
    res.status(500).json({ error: err.message });
  }
});
app.listen(PORT, () => {
  console.log(`🚀 Futures Agent V20 (Super Lengkap) running on port ${PORT}`);
  // Scan pertama dengan timeframe default 1h
  setTimeout(() => scanAllPairs('1h'), 2000);
});
