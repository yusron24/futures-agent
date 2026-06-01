// ─── Analisis AI dengan Claude Sonnet 4.6 via Dinoiki ───
async function analyzeWithAgent(symbol) {
  console.log(`[${symbol}] Memulai analisis...`);
  
  const candles = await fetchCandles(symbol);
  if (!candles) {
    console.log(`[${symbol}] Gagal mengambil candle`);
    return null;
  }
  
  const [oi, funding, lsRatio, ticker] = await Promise.all([
    axios.get(`https://fapi.binance.com/fapi/v1/openInterest?symbol=${symbol}`),
    axios.get(`https://fapi.binance.com/fapi/v1/fundingInfo?symbol=${symbol}`),
    axios.get(`https://fapi.binance.com/fapi/v1/globalLongShortAccountRatio?symbol=${symbol}&period=1h&limit=1`),
    axios.get(`https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=${symbol}`)
  ]);
  
  const pa = analyzePriceAction(candles);
  if (!pa) {
    console.log(`[${symbol}] Gagal analisis price action`);
    return null;
  }
  
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
    const AI_API_KEY = process.env.AI_API_KEY; 'sk-284100b0920d81e0b5a5c8f6fca7316f2a965a6055f89ba7'
    const AI_API_URL = process.env.AI_API_URL || 'https://ai.dinoiki.com/v1/chat/completions';

    if (!AI_API_KEY) {
      console.error(`[${symbol}] ❌ AI_API_KEY tidak ditemukan di Environment Variables!`);
      return { action: 'WAIT', confidence: 0 };
    }

    // ⚠️ Format OpenAI untuk Dinoiki
    const requestData = {
      model: 'claude-sonnet-4-6',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userMessage }
      ],
      max_tokens: 500,
      temperature: 0.1
    };

    console.log(`[${symbol}] Mengirim request ke Dinoiki...`);
    const res = await axios.post(AI_API_URL, requestData, {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AI_API_KEY}`
      },
      timeout: 60000
    });

    console.log(`[${symbol}] ✅ Response diterima dari Dinoiki`);

    const content = res.data.choices[0].message.content;
    const cleaned = content.replace(/```json|```/g, '').trim();
    const decision = JSON.parse(cleaned);
    
    if (decision.action !== 'WAIT') {
      const risk = Math.abs(decision.entry - decision.stopLoss);
      const reward = Math.abs(decision.takeProfit - decision.entry);
      if (risk > 0 && reward / risk < 2) decision.action = 'WAIT';
      if (decision.confidence < 90) decision.action = 'WAIT';
    }
    
    console.log(`[${symbol}] Keputusan: ${decision.action} (Confidence: ${decision.confidence}%)`);
    return decision;
  } catch (error) {
    console.error(`[${symbol}] ❌ Error Dinoiki API:`, error.response?.data || error.message);
    return { action: 'WAIT', confidence: 0 };
  }
}
