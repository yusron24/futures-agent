// server.js - V21 (Level-Based SL/TP & RR ≥ 2)
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const NodeCache = require('node-cache');

const app = express();
app.use(cors());
app.use(express.json());

const cache = new NodeCache({ stdTTL: 60 });
const detailCache = new NodeCache({ stdTTL: 60 });
const SCAN_INTERVAL = 10000;
const MAX_PAIRS = 5000;
const CONFIDENCE_THRESHOLD = 60;

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

// ─── Identifikasi Level Kunci (Support & Resistance) ───
function identifyKeyLevels(candles) {
  // Gunakan 30 candle terakhir untuk mencari swing high & low
  const highs = candles.slice(-30).map(c => parseFloat(c[2]));
  const lows = candles.slice(-30).map(c => parseFloat(c[3]));
  const lastClose = parseFloat(candles[candles.length - 1][4]);
  const lastHigh = parseFloat(candles[candles.length - 1][2]);
  const lastLow = parseFloat(candles[candles.length - 1][3]);

  // Cari level resistance utama (high terbesar dalam 30 candle)
  const resistance = Math.max(...highs);
  // Cari level support utama (low terbesar dalam 30 candle)
  const support = Math.min(...lows);

  return { resistance, support };
}

// ─── Analisis Price Action ───
function analyzePriceAction(candles) {
  if (!candles || candles.length < 5) return { score: 0, signals: [], trend: 'SIDEWAYS', volumeRatio: 0, support: 0, resistance: 0 };

  const last = candles[candles.length - 1];
  const prev = candles[candles.length - 2];
  const prev2 = candles[candles.length - 3] || prev;

  const close = parseFloat(last[4]);
  const open = parseFloat(last[1]);
  const high = parseFloat(last[2]);
  const low = parseFloat(last[3]);
  const volume = parseFloat(last[5]);

  const prevClose = parseFloat(prev[4]);
  const prevHigh = parseFloat(prev[2]);
  const prevLow = parseFloat(prev[3]);

  const body = Math.abs(close - open);
  const range = high - low;
  const bodyRatio = body / (range || 0.001);
  const upperWick = high - Math.max(open, close);
  const lowerWick = Math.min(open, close) - low;

  const volumes = candles.map(c => parseFloat(c[5]));
  const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
  const volumeRatio = volume / (avgVolume || 1);
  const isVolumeSpike = volumeRatio > 2.0;

  // Identifikasi level kunci (Support & Resistance)
  const { resistance, support } = identifyKeyLevels(candles);

  let score = 0;
  let signals = [];

  // 1. Bullish / Bearish Engulfing
  if (open > prevClose && close > prevHigh && body > prevClose * 0.02) {
    score += 15; signals.push('Bullish Engulfing');
  } else if (open < prevClose && close < prevLow && body > prevClose * 0.02) {
    score -= 15; signals.push('Bearish Engulfing');
  }

  // 2. Pin Bar (Hammer / Shooting Star)
  if (lowerWick > body * 2.5 && lowerWick > range * 0.3 && close > open) {
    score += 12; signals.push('Hammer');
  } else if (upperWick > body * 2.5 && upperWick > range * 0.3 && close < open) {
    score -= 12; signals.push('Shooting Star');
  }

  // 3. Doji
  if (body < range * 0.15) {
    if (close > open) { score += 5; signals.push('Doji Bullish'); }
    else { score -= 5; signals.push('Doji Bearish'); }
  }

  // 4. Marubozu
  if (body > range * 0.85) {
    if (close > open) { score += 10; signals.push('Bullish Marubozu'); }
    else { score -= 10; signals.push('Bearish Marubozu'); }
  }

  // 5. Volume Spike
  if (isVolumeSpike) {
    if (close > open) {
      score += 20; signals.push('Volume Spike Bullish');
    } else {
      score -= 20; signals.push('Volume Spike Bearish');
    }
  }

  // 6. Level Support/Resistance
  const nearResistance = (resistance - close) / close < 0.015;
  const nearSupport = (close - support) / close < 0.015;

  if (nearSupport && close > open) {
    score += 10; signals.push('Near Support (Bullish)');
  } else if (nearResistance && close < open) {
    score -= 10; signals.push('Near Resistance (Bearish)');
  }

  return { score, signals: signals.slice(0, 6), trend: score > 10 ? 'BULLISH' : score < -10 ? 'BEARISH' : 'SIDEWAYS', volumeRatio, support, resistance };
}

// ─── Fungsi Utama Analisis (Full) ───
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
    const candles = await fetchBinanceCandles(symbol, interval, 100);
    if (!candles || candles.length < 20) return null;

    const pa = analyzePriceAction(candles);
    const coinglassData = await fetchCoinglassData(symbol);

    let finalScore = pa.score;

    // Bonus untuk konfirmasi level
    if (pa.trend === 'BULLISH' && pa.support > 0) finalScore += 5;
    if (pa.trend === 'BEARISH' && pa.resistance > 0) finalScore += 5;

    // Derivatif (Coinglass)
    if (coinglassData.openInterest > 0 && finalScore > 0) finalScore += 5;
    if (coinglassData.cvd > 0 && finalScore > 0) finalScore += 5;
    if (coinglassData.liquidationHeatmap > 0 && finalScore > 0) finalScore += 5;

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
    } catch (err) {}

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

    // ─────────────────────────────────────────────────────────────────────────
    //  LEVEL-BASED SL & TP (Area Invalidasi & Likuiditas)
    // ─────────────────────────────────────────────────────────────────────────
    const price = parseFloat(candles[candles.length - 1][4]);
    const atr = (parseFloat(candles[candles.length - 1][2]) - parseFloat(candles[candles.length - 1][3])) * 0.5;
    const tickSize = 0.00001; // Tick size minimal (bisa disesuaikan per pair)

    let entry = price;
    let stopLoss = 0;
    let takeProfit1 = 0;
    let riskRewardRatio = 0;

    if (signal === 'LONG') {
      // Area Invalidasi (SL) : Support Terdekat - Buffer
      const invalidationLevel = pa.support > 0 ? pa.support : price - atr * 1.5;
      stopLoss = invalidationLevel - (tickSize * 2);

      // Area Likuiditas (TP) : Resistance Terdekat - Buffer (area pengambilan profit)
      const liquidityLevel = pa.resistance > 0 ? pa.resistance : price + atr * 2.5;
      takeProfit1 = liquidityLevel - (tickSize * 2);

      // Pastikan SL < Entry < TP
      if (stopLoss >= entry) stopLoss = entry - atr * 0.5;
      if (takeProfit1 <= entry) takeProfit1 = entry + atr * 2.0;

      // Hitung RR Ratio dan sesuaikan jika perlu
      const risk = entry - stopLoss;
      const reward = takeProfit1 - entry;
      riskRewardRatio = reward / risk;

      // Jika RR < 2, coba gunakan level resistance yang lebih tinggi (likuiditas lebih luas)
      if (riskRewardRatio < 2 && pa.resistance > 0) {
        // Cari resistance kedua (dari 50 candle)
        const highs = candles.slice(-50).map(c => parseFloat(c[2]));
        highs.sort((a, b) => b - a);
        const secondResistance = highs.length > 1 ? highs[1] : pa.resistance + atr * 2;
        const newTP = secondResistance - (tickSize * 2);
        if (newTP > entry + risk * 2) {
          takeProfit1 = newTP;
          const newReward = takeProfit1 - entry;
          riskRewardRatio = newReward / risk;
        }
      }
    } else if (signal === 'SHORT') {
      // Area Invalidasi (SL) : Resistance Terdekat + Buffer
      const invalidationLevel = pa.resistance > 0 ? pa.resistance : price + atr * 1.5;
      stopLoss = invalidationLevel + (tickSize * 2);

      // Area Likuiditas (TP) : Support Terdekat + Buffer (area pengambilan profit)
      const liquidityLevel = pa.support > 0 ? pa.support : price - atr * 2.5;
      takeProfit1 = liquidityLevel + (tickSize * 2);

      // Pastikan Entry > SL > TP (untuk short)
      if (stopLoss <= entry) stopLoss = entry + atr * 0.5;
      if (takeProfit1 >= entry) takeProfit1 = entry - atr * 2.0;

      // Hitung RR Ratio dan sesuaikan jika perlu
      const risk = stopLoss - entry;
      const reward = entry - takeProfit1;
      riskRewardRatio = reward / risk;

      // Jika RR < 2, coba gunakan level support yang lebih rendah (likuiditas lebih luas)
      if (riskRewardRatio < 2 && pa.support > 0) {
        // Cari support kedua (dari 50 candle)
        const lows = candles.slice(-50).map(c => parseFloat(c[3]));
        lows.sort((a, b) => a - b);
        const secondSupport = lows.length > 1 ? lows[1] : pa.support - atr * 2;
        const newTP = secondSupport + (tickSize * 2);
        if (newTP < entry - risk * 2) {
          takeProfit1 = newTP;
          const newReward = entry - takeProfit1;
          riskRewardRatio = newReward / risk;
        }
      }
    }

    // Final validation: Pastikan RR ≥ 2
    if (signal !== 'WAIT' && riskRewardRatio < 2) {
      signal = 'WAIT';
      confidence = 0;
    }

    console.log(`📊 [${symbol}] TF: ${timeframe} | Score: ${finalScore.toFixed(1)} | Signal: ${signal} | Conf: ${confidence} | RR: ${riskRewardRatio.toFixed(2)}:1 | SL: ${stopLoss.toFixed(8)} | TP: ${takeProfit1.toFixed(8)} | OI: ${coinglassData.openInterest.toFixed(0)}`);

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

// ─── Scheduler ───
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
    const promises = batch.map(async (s) => {
      const analysis = await analyzeFull(s, timeframe);
      if (analysis) {
        const cacheKey = `${s}_${timeframe}`;
        detailCache.set(cacheKey, analysis, 120);
      }
      return analysis;
    });
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

// ─── Endpoint Scan ───
app.post('/api/v1/scan', async (req, res) => {
  const { timeframe = '1h' } = req.body;
  await scanAllPairs(timeframe);
  res.json({ success: true, message: `Scan completed for ${timeframe}` });
});

// ─── Endpoint Sinyal ───
app.get('/api/v1/signals', (req, res) => {
  res.json({
    success: true,
    signals: scanResults,
    total: scanResults.length,
    lastScan: lastScanTime,
    scanning: isScanning
  });
});

// ─── Endpoint Detail Sinyal ───
app.get('/api/v1/signal/:symbol', async (req, res) => {
  const symbol = req.params.symbol;
  const timeframe = req.query.timeframe || '1h';
  const cacheKey = `${symbol}_${timeframe}`;

  const cachedAnalysis = detailCache.get(cacheKey);
  if (cachedAnalysis) {
    return res.json({ success: true, signal: cachedAnalysis });
  }

  try {
    const analysis = await analyzeFull(symbol, timeframe);
    if (!analysis) {
      return res.status(404).json({ error: 'Data not found' });
    }
    detailCache.set(cacheKey, analysis, 120);
    res.json({ success: true, signal: analysis });
  } catch (err) {
    console.error(`❌ Error fetching detail for ${symbol}:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Debug ───
app.get('/debug/fapi', async (req, res) => {
  try {
    const response = await axios.get('https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT', axiosConfig);
    res.json({ success: true, data: response.data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 10000;
app.listen(PORT, () => {
  console.log(`🚀 Futures Agent V21 (Level-Based RR≥2) running on port ${PORT}`);
  setTimeout(() => scanAllPairs('1h'), 2000);
});
