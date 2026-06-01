require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const NodeCache = require('node-cache');

const app = express();
app.use(cors());
app.use(express.json());

const cache = new NodeCache({ stdTTL: 60 });
const SCAN_INTERVAL = 60000;
const MAX_PAIRS = 30;
const CONFIDENCE_THRESHOLD = 90;

// ⚠️ Ambil Environment Variables. Jika gagal, aplikasi tetap jalan dengan pesan error
const AI_API_KEY = process.env.AI_API_KEY; 
const AI_API_URL = process.env.AI_API_URL || 'https://ai.dinoiki.com/v1/chat/completions';

// Tambahkan pengecekan API Key saat startup
if (!AI_API_KEY) {
  console.error('⚠️ PERINGATAN: AI_API_KEY tidak ditemukan! Sinyal tidak akan dihasilkan.');
}

let scanResults = [];
let lastScanTime = null;
let isScanning = false;
let scanCount = 0;

// ─── 1. Ambil 30 pair dengan volume tertinggi ───
async function getTopVolumeSymbols() {
  const cacheKey = 'top_volume_symbols';
  const cached = cache.get(cacheKey);
  if (cached) return cached;
  try {
    const { data: tickers } = await axios.get('https://fapi.binance.com/fapi/v1/ticker/24hr');
    const usdtTickers = tickers.filter(t => t.symbol.endsWith('USDT'));
    usdtTickers.sort((a, b) => parseFloat(b.quoteVolume) - parseFloat(a.quoteVolume));
    const symbols = usdtTickers.slice(0, MAX_PAIRS).map(t => t.symbol);
    cache.set(cacheKey, symbols, 3600);
    return symbols;
  } catch { return ['BTCUSDT', 'ETHUSDT', 'SOLUSDT']; }
}

// ─── 2. Ambil 500 candle 1h ───
async function fetchCandles(symbol) {
  try {
    const { data } = await axios.get(`https://fapi.binance.com/fapi/v1/klines?symbol=${symbol}&interval=1h&limit=500`);
    return data;
  } catch { return null; }
}

// ─── 3. Analisis Price Action ───
function analyzePriceAction(candles) {
  if (!candles || candles.length < 500) return null;
  const last = candles[candles.length - 1];
  const prev = candles[candles.length - 2];
  const close = parseFloat(last[4]), open = parseFloat(last[1]), high = parseFloat(last[2]), low = parseFloat(last[3]), vol = parseFloat(last[5]);
  const body = Math.abs(close - open), range = high - low;
  const bodyRatio = range > 0 ? body / range : 0;
  const upperWick = high - Math.max(open, close), lowerWick = Math.min(open, close) - low;
  
  const highs = candles.map(c => parseFloat(c[2]));
  const lows = candles.map(c => parseFloat(c[3]));
  const resistance = Math.max(...highs);
  const support = Math.min(...lows);
  
  const volumes = candles.map(c => parseFloat(c[5]));
  const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
  const volRatio = avgVolume > 0 ? vol / avgVolume : 1;
  
  let patterns = [];
  if (open > parseFloat(prev[4]) && close > parseFloat(prev[2]) && body > parseFloat(prev[4]) * 0.02)
    patterns.push('Bullish Engulfing');
  if (open < parseFloat(prev[4]) && close < parseFloat(prev[3]) && body > parseFloat(prev[4]) * 0.02)
    patterns.push('Bearish Engulfing');
  if (lowerWick > body * 2.5 && lowerWick > range * 0.3 && close > open)
    patterns.push('Hammer');
  if (upperWick > body * 2.5 && upperWick > range * 0.3 && close < open)
    patterns.push('Shooting Star');
  if (body < range * 0.15)
    patterns.push(close > open ? 'Doji Bullish' : 'Doji Bearish');
  if (body > range * 0.85)
    patterns.push(close > open ? 'Marubozu Bullish' : 'Marubozu Bearish');
  
  return { close, high, low, open, support, resistance, volRatio, patterns, bodyRatio, upperWick, lowerWick };
}

// ─── 4. Analisis AI dengan Claude Sonnet 4.6 via Dinoiki ───
async function analyzeWithAgent(symbol) {
  if (!AI_API_KEY) {
    console.warn(`[${symbol}] AI_API_KEY tidak ada, dilewati.`);
    return { action: 'WAIT', confidence: 0 };
  }

  const candles = await fetchCandles(symbol);
  if (!candles) return null;
  
  const [oi, funding, lsRatio, ticker] = await Promise.all([
    axios.get(`https://fapi.binance.com/fapi/v1/openInterest?symbol=${symbol}`),
    axios.get(`https://fapi.binance.com/fapi/v1/fundingInfo?symbol=${symbol}`),
    axios.get(`https://fapi.binance.com/fapi/v1/globalLongShortAccountRatio?symbol=${symbol}&period=1h&limit=1`),
    axios.get(`https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=${symbol}`)
  ]);
  
  const pa = analyzePriceAction(candles);
  if (!pa) return null;
  
  const oiValue = parseFloat(oi.data.sumOpenInterestValue || 0);
  const fundingRate = parseFloat(funding.data[0]?.fundingRate || 0);
  const ls = parseFloat(lsRatio.data[0]?.longShortRatio || 1);
  const price = parseFloat(ticker.data.lastPrice);
  
  const systemPrompt = `
Anda adalah AI Agent trading futures crypto profesional. Tugas Anda adalah menganalisis data pasar dan memberikan sinyal trading (LONG/SHORT/WAIT). 
Anda harus mengembalikan respons Anda sebagai objek JSON mentah. 
JSON harus berisi: "action" (LONG/SHORT/WAIT), "entry" (harga saat ini), "stopLoss" (level invalidasi), "takeProfit" (level likuiditas), "confidence" (0-100), "reasoning" (penjelasan singkat), dan "rr" (rasio risk:reward). 
Semua level harus presisi. Confidence harus >= 90. RR harus >= 2. Jangan gunakan format markdown.
`;

  const userMessage = `
Data pasar untuk ${symbol} (500 candle 1h):
- Harga saat ini: ${price}
- Support terdekat: ${pa.support.toFixed(2)}
- Resistance terdekat: ${pa.resistance.toFixed(2)}
- Body Ratio: ${pa.bodyRatio.toFixed(2)}
- Upper Wick: ${pa.upperWick.toFixed(4)}, Lower Wick: ${pa.lowerWick.toFixed(4)}
- Volume Ratio: ${pa.volRatio.toFixed(2)}
- Pola terdeteksi: ${pa.patterns.join(', ') || 'Tidak ada'}
- Open Interest: ${oiValue.toFixed(0)}
- Funding Rate: ${(fundingRate * 100).toFixed(4)}%
- Long/Short Ratio: ${ls.toFixed(2)}
`;

  try {
    const requestData = {
      model: 'claude-sonnet-4-6',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userMessage }
      ],
      max_tokens: 500,
      temperature: 0.1
    };

    const res = await axios.post(AI_API_URL, requestData, {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AI_API_KEY}`
      },
      timeout: 60000
    });

    const content = res.data.choices[0].message.content;
    const cleaned = content.replace(/```json|```/g, '').trim();
    const decision = JSON.parse(cleaned);
    
    if (decision.action !== 'WAIT') {
      const risk = Math.abs(decision.entry - decision.stopLoss);
      const reward = Math.abs(decision.takeProfit - decision.entry);
      if (risk > 0 && reward / risk < 2) decision.action = 'WAIT';
      if (decision.confidence < 90) decision.action = 'WAIT';
    }
    return decision;
  } catch (error) {
    console.error(`[${symbol}] Error Dinoiki API:`, error.response?.data || error.message);
    return { action: 'WAIT', confidence: 0 };
  }
}

// ─── 5. Scheduler ───
async function scanAllPairs() {
  if (isScanning) return;
  isScanning = true;
  scanCount++;
  console.log(`\n🤖 SCAN #${scanCount} dimulai...`);
  const symbols = await getTopVolumeSymbols();
  console.log(`🔍 Memindai ${symbols.length} pasangan...`);
  const results = [];

  for (let i = 0; i < symbols.length; i += 5) {
    const batch = symbols.slice(i, i + 5);
    const promises = batch.map(async s => {
      const decision = await analyzeWithAgent(s);
      if (decision && decision.action !== 'WAIT') {
        return { 
          symbol: s, 
          signal: decision.action, 
          entry: decision.entry, 
          stopLoss: decision.stopLoss, 
          takeProfit: decision.takeProfit, 
          confidence: decision.confidence, 
          reasoning: decision.reasoning 
        };
      }
      return null;
    });
    const batchResults = await Promise.allSettled(promises);
    batchResults.forEach(r => { if (r.status === 'fulfilled' && r.value) results.push(r.value); });
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  scanResults = results;
  lastScanTime = new Date();
  isScanning = false;
  console.log(`✅ Selesai. Sinyal: ${scanResults.length}`);
}

// ─── 6. API ───
app.get('/api/v1/signals', (req, res) => res.json({ 
  success: true, 
  signals: scanResults, 
  total: scanResults.length, 
  lastScan: lastScanTime, 
  scanning: isScanning 
}));

app.get('/api/v1/signal/:symbol', async (req, res) => {
  const decision = await analyzeWithAgent(req.params.symbol);
  res.json({ success: true, signal: decision });
});

// ─── 7. Start Server ───
const PORT = process.env.PORT || 10000;
app.listen(PORT, () => {
  console.log(`🤖 AI Agent (Dinoiki) running on port ${PORT}`);
  console.log('⏳ Memulai scan pertama dalam 3 detik...');
  // Jalankan scan pertama setelah server siap
  setTimeout(scanAllPairs, 3000);
});

// Scan selanjutnya berjalan otomatis setiap interval
setInterval(scanAllPairs, SCAN_INTERVAL);
