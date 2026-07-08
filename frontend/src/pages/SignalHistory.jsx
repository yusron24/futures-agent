import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getSignalHistory } from '../api/client';
import { TableSkeleton } from '../components/Skeleton';
import ScoreBadge from '../components/ScoreBadge';
import { formatPrice, formatPercent, changeColor } from '../utils/format';

export default function SignalHistory() {
  const navigate = useNavigate();
  const [signals, setSignals] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getSignalHistory({ limit: 200 })
      .then(setSignals)
      .finally(() => setLoading(false));
  }, []);

  return (
    <div>
      <h1 className="text-xl font-bold text-terminal-text mb-1">Riwayat Sinyal</h1>
      <p className="text-xs text-terminal-muted mb-4">
        Log koin yang pernah melewati skor threshold, direkam setiap siklus screening (default setiap 5 menit).
      </p>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg overflow-hidden">
        {loading ? (
          <TableSkeleton rows={8} />
        ) : signals.length === 0 ? (
          <div className="text-center py-16 text-terminal-muted text-sm">
            Belum ada sinyal yang tercatat. Sinyal muncul otomatis saat suatu koin melewati skor threshold.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-terminal-muted border-b border-terminal-border uppercase text-[11px] tracking-wider">
                <th className="px-4 py-3 font-medium">Waktu</th>
                <th className="px-2 py-3 font-medium">Koin</th>
                <th className="px-2 py-3 font-medium text-right">Harga</th>
                <th className="px-2 py-3 font-medium text-right">24h</th>
                <th className="px-2 py-3 font-medium text-right">Vol Spike</th>
                <th className="px-2 py-3 font-medium text-right">RSI</th>
                <th className="px-2 py-3 font-medium text-right">Skor</th>
              </tr>
            </thead>
            <tbody>
              {signals.map((s) => (
                <tr
                  key={s.id}
                  className="border-b border-terminal-border/50 hover:bg-white/5 cursor-pointer"
                  onClick={() => navigate(`/coin/${s.coin_id}`)}
                >
                  <td className="px-4 py-3 text-terminal-muted text-xs">{new Date(s.created_at + 'Z').toLocaleString('id-ID')}</td>
                  <td className="px-2 py-3 font-semibold">{s.symbol}</td>
                  <td className="px-2 py-3 text-right font-mono">{formatPrice(s.price)}</td>
                  <td className={`px-2 py-3 text-right font-mono ${changeColor(s.change_24h)}`}>{formatPercent(s.change_24h)}</td>
                  <td className="px-2 py-3 text-right font-mono">{s.volume_spike != null ? `${s.volume_spike.toFixed(2)}x` : '-'}</td>
                  <td className="px-2 py-3 text-right font-mono">{s.rsi != null ? s.rsi.toFixed(0) : '-'}</td>
                  <td className="px-2 py-3 text-right"><ScoreBadge score={s.score} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
