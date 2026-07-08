import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getRsiScreener } from '../api/client';
import { TableSkeleton } from '../components/Skeleton';
import CoinAvatar from '../components/CoinAvatar';
import useInterval from '../hooks/useInterval';
import { formatPrice, formatPercent, changeColor, timeAgo } from '../utils/format';

const POLL_MS = 30000;

export default function RsiScreener() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await getRsiScreener();
      setData(res);
      setError(null);
    } catch (err) {
      setError(err.response?.data?.error || 'Gagal memuat RSI screener.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  useInterval(load, POLL_MS);

  return (
    <div>
      <div className="flex items-center justify-between mb-1">
        <h1 className="text-xl font-bold text-terminal-text">RSI Screener</h1>
      </div>
      <p className="text-xs text-terminal-muted mb-4">
        Pair Binance Futures yang sedang oversold (RSI &lt; 30, berpotensi rebound) atau overbought (RSI &gt; 70,
        berpotensi koreksi) — murni indikator teknikal, bukan sinyal beli/jual. Dihitung dari seluruh universe
        screening setiap siklus (tidak ada lagi pemindaian bergilir terpisah).
      </p>

      {data && (
        <div className="flex flex-wrap gap-4 text-xs text-terminal-muted mb-4 px-4 py-3 bg-terminal-panel border border-terminal-border rounded-lg">
          <span>
            Dianalisis: <b className="text-terminal-text">{data.scannedCount}</b> / {data.poolSize} pair
          </span>
          <span>Update terakhir: {data.updatedAt ? timeAgo(data.updatedAt) : 'belum ada'}</span>
        </div>
      )}

      {error && (
        <div className="mb-4 px-4 py-3 rounded bg-terminal-red/10 border border-terminal-red/30 text-terminal-red text-sm">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <RsiTable
          title="Oversold (RSI < 30)"
          hint="Berpotensi rebound"
          accentClass="text-terminal-green border-terminal-green/30"
          coins={data?.oversold}
          loading={loading}
        />
        <RsiTable
          title="Overbought (RSI > 70)"
          hint="Berpotensi koreksi"
          accentClass="text-terminal-red border-terminal-red/30"
          coins={data?.overbought}
          loading={loading}
        />
      </div>
    </div>
  );
}

function RsiTable({ title, hint, accentClass, coins, loading }) {
  const navigate = useNavigate();

  return (
    <div className="bg-terminal-panel border border-terminal-border rounded-lg overflow-hidden">
      <div className={`px-4 py-3 border-b ${accentClass} flex items-center justify-between`}>
        <span className="font-semibold text-sm">{title}</span>
        <span className="text-[10px] text-terminal-muted">{hint}</span>
      </div>

      {loading && !coins ? (
        <TableSkeleton rows={5} />
      ) : !coins || coins.length === 0 ? (
        <div className="text-center py-10 text-terminal-muted text-sm">
          Belum ada koin yang cocok di pool yang sudah dipindai.
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-terminal-muted border-b border-terminal-border uppercase text-[11px] tracking-wider">
              <th className="px-4 py-2 font-medium">Pair</th>
              <th className="px-2 py-2 font-medium text-right">Harga</th>
              <th className="px-2 py-2 font-medium text-right">24h</th>
              <th className="px-2 py-2 font-medium text-right">RSI</th>
            </tr>
          </thead>
          <tbody>
            {coins.map((coin) => (
              <tr
                key={coin.id}
                onClick={() => navigate(`/coin/${coin.id}`)}
                className="border-b border-terminal-border/50 hover:bg-white/5 cursor-pointer animate-fade-in"
              >
                <td className="px-4 py-2.5">
                  <div className="flex items-center gap-2">
                    <CoinAvatar symbol={coin.symbol} />
                    <span className="font-semibold text-terminal-text">{coin.symbol}</span>
                  </div>
                </td>
                <td className="px-2 py-2.5 text-right font-mono">{formatPrice(coin.price)}</td>
                <td className={`px-2 py-2.5 text-right font-mono ${changeColor(coin.change24h)}`}>
                  {formatPercent(coin.change24h)}
                </td>
                <td className={`px-2 py-2.5 text-right font-mono font-bold ${accentClass.split(' ')[0]}`}>
                  {coin.rsi.toFixed(1)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
