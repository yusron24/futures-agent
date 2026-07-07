import React, { useState, useEffect, useCallback } from 'react';
import axios from 'axios';

const API_URL = 'https://futures-agent.onrender.com';

export default function App() {
  const [signals, setSignals] = useState([]);
  const [selectedSignal, setSelectedSignal] = useState(null);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState(null);
  const [timeframe, setTimeframe] = useState('1h');
  const [isScanning, setIsScanning] = useState(false);

  const fetchSignals = useCallback(async () => {
    try {
      const res = await axios.get(`${API_URL}/api/v1/signals`);
      const sortedSignals = (res.data.signals || [])
        .sort((a, b) => b.confidence - a.confidence);
      setSignals(sortedSignals);
      setStatus(res.data);
    } catch (err) {
      console.error('❌ Gagal mengambil sinyal:', err);
    }
  }, []);

  const handleScan = useCallback(async (tf) => {
    setIsScanning(true);
    try {
      await axios.post(`${API_URL}/api/v1/scan`, { timeframe: tf });
      await fetchSignals();
    } catch (err) {
      console.error('❌ Gagal scan:', err);
    } finally {
      setIsScanning(false);
    }
  }, [fetchSignals]);

  const fetchDetail = useCallback(async (symbol) => {
    setLoading(true);
    try {
      const res = await axios.get(`${API_URL}/api/v1/signal/${symbol}`);
      setSelectedSignal(res.data.signal);
    } catch (err) {
      console.error('❌ Gagal mengambil detail:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSignals();
    const interval = setInterval(fetchSignals, 30000);
    return () => clearInterval(interval);
  }, [fetchSignals]);

  return (
    <div style={{ background: '#040d1a', minHeight: '100vh', color: '#cdd6f4', padding: '10px', fontFamily: "'Rajdhani',sans-serif" }}>
      {/* Header */}
      <div style={{ background: '#060e1c', padding: '10px 16px', borderRadius: 8, marginBottom: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ color: '#00d4ff', fontWeight: 700, letterSpacing: '2.5px', fontSize: 14 }}>
          ⚡ FUTURES AI V20 — SUPER SCANNER
        </span>
        <div style={{ fontSize: 11, color: '#2e4a6a' }}>
          Signals: <b style={{ color: '#00e676' }}>{signals.length}</b> | 
          Last scan: {status?.lastScan ? new Date(status.lastScan).toLocaleTimeString() : '...'}
        </div>
      </div>

      {/* Timeframe Selector */}
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 10 }}>
        {['5m', '15m', '1h', '4h', '1d'].map(tf => (
          <button
            key={tf}
            onClick={() => {
              setTimeframe(tf);
              handleScan(tf);
            }}
            disabled={isScanning}
            style={{
              padding: '4px 12px',
              borderRadius: 4,
              border: `1px solid ${timeframe === tf ? '#00d4ff44' : '#0a1e35'}`,
              background: timeframe === tf ? 'rgba(0,212,255,0.1)' : 'transparent',
              color: timeframe === tf ? '#00d4ff' : '#2e4a6a',
              fontSize: 11,
              fontWeight: 700,
              cursor: isScanning ? 'not-allowed' : 'pointer'
            }}
          >
            {tf}
          </button>
        ))}
        {isScanning && <span style={{ color: '#ffb300', fontSize: 11 }}>⏳ Scanning...</span>}
      </div>

      {/* Signal List */}
      <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 280, maxHeight: '80vh', overflow: 'auto' }}>
          <div style={{ background: '#060e1c', borderRadius: 8, border: '1px solid #091829', padding: '12px' }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: '#2e4a6a', marginBottom: 8 }}>
              📊 HIGH CONFIDENCE SIGNALS ({signals.length})
            </div>
            {signals.length === 0 ? (
              <div style={{ padding: '20px', textAlign: 'center', color: '#1b3354', fontSize: 11 }}>
                No signals found
              </div>
            ) : (
              signals.map(s => (
                <div
                  key={s.symbol}
                  onClick={() => fetchDetail(s.symbol)}
                  style={{
                    padding: '6px 10px',
                    marginBottom: 4,
                    background: selectedSignal?.symbol === s.symbol ? '#0b2040' : '#091829',
                    borderRadius: 4,
                    cursor: 'pointer',
                    border: `1px solid ${selectedSignal?.symbol === s.symbol ? '#00d4ff44' : '#0b2040'}`
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ fontWeight: 700, color: '#8899b4' }}>{s.symbol}</span>
                    <span>
                      <span style={{ color: s.signal === 'LONG' ? '#00e676' : '#ff3860', fontWeight: 700 }}>
                        {s.signal}
                      </span>
                      <span style={{ marginLeft: 8, color: '#00d4ff', fontWeight: 700 }}>{s.confidence}%</span>
                      <span style={{ marginLeft: 4, color: '#ffb300' }}>⚡</span>
                    </span>
                  </div>
                  <div style={{ fontSize: 9, color: '#1b3354', marginTop: 2 }}>
                    Score: {s.score} · Vol: {s.volumeRatio}x · {s.timeframe}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Detail Panel */}
        <div style={{ flex: 1, minWidth: 280 }}>
          <div style={{ background: '#060e1c', borderRadius: 8, border: '1px solid #091829', padding: '12px', minHeight: '300px' }}>
            {loading ? (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#2e4a6a' }}>Loading...</div>
            ) : !selectedSignal ? (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#1b3354' }}>
                Klik sinyal di kiri untuk lihat detail
              </div>
            ) : (
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 10 }}>
                  <h2 style={{ fontSize: 20, color: '#00d4ff', margin: 0 }}>{selectedSignal.symbol}</h2>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ fontSize: 9, color: '#2e4a6a' }}>CONFIDENCE</div>
                    <div style={{ fontSize: 28, fontWeight: 700, color: '#00d4ff' }}>{selectedSignal.confidence}%</div>
                  </div>
                </div>

                {/* Entry, SL, TP */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 4, marginBottom: 10 }}>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4, textAlign: 'center' }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>ENTRY</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#00d4ff' }}>{selectedSignal.entry}</div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4, textAlign: 'center' }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>STOP LOSS</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#ff3860' }}>{selectedSignal.stopLoss}</div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4, textAlign: 'center' }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>TAKE PROFIT 1</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#00e676' }}>{selectedSignal.takeProfit1}</div>
                  </div>
                </div>

                {/* Signals List */}
                <div style={{ background: '#091829', padding: '8px', borderRadius: 4, marginBottom: 10 }}>
                  <div style={{ fontSize: 8, color: '#2e4a6a', letterSpacing: '1px' }}>SIGNALS</div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 4 }}>
                    {selectedSignal.signals?.map((s, i) => (
                      <span key={i} style={{ background: '#0b2040', padding: '2px 8px', borderRadius: 3, fontSize: 9, color: '#8899b4' }}>{s}</span>
                    ))}
                  </div>
                </div>

                {/* Derivatives */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4, marginBottom: 10 }}>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>OPEN INTEREST</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#b388ff' }}>{selectedSignal.derivatives?.oi || 'N/A'}</div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>CVD</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#b388ff' }}>{selectedSignal.derivatives?.cvd || 'N/A'}</div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>LIQUIDATION HEATMAP</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: '#b388ff' }}>{selectedSignal.derivatives?.liquidation || 'N/A'}</div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>FUNDING RATE</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: parseFloat(selectedSignal.derivatives?.funding || 0) > 0 ? '#ffb300' : '#00d4ff' }}>
                      {selectedSignal.derivatives?.funding || 'N/A'}
                    </div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>LONG/SHORT RATIO</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: parseFloat(selectedSignal.derivatives?.lsRatio || 0) > 1.5 ? '#ff3860' : '#00e676' }}>
                      {selectedSignal.derivatives?.lsRatio || 'N/A'}
                    </div>
                  </div>
                  <div style={{ background: '#091829', padding: '6px', borderRadius: 4 }}>
                    <div style={{ fontSize: 8, color: '#2e4a6a' }}>VOLUME RATIO</div>
                    <div style={{ fontSize: 14, fontWeight: 700, color: selectedSignal.volumeRatio > 2 ? '#ffb300' : '#8899b4' }}>
                      {selectedSignal.volumeRatio}x
                    </div>
                  </div>
                </div>

                {/* Trend, Strength, Score */}
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: '#2e4a6a' }}>
                  <span>Trend: <b style={{ color: selectedSignal.trend === 'BULLISH' ? '#00e676' : '#ff3860' }}>{selectedSignal.trend}</b></span>
                  <span>Strength: <b>{selectedSignal.strength}</b></span>
                  <span>Score: <b>{selectedSignal.score}</b></span>
                  <span>Timeframe: <b>{selectedSignal.timeframe}</b></span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
