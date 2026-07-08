import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getWatchlist, removeFromWatchlist, getScreening } from '../api/client';
import ScoreBadge from '../components/ScoreBadge';
import { TableSkeleton } from '../components/Skeleton';
import { formatPrice, formatPercent, changeColor } from '../utils/format';

export default function Watchlist() {
  const navigate = useNavigate();
  const [watchlist, setWatchlist] = useState([]);
  const [scores, setScores] = useState({});
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [list, screening] = await Promise.all([getWatchlist(), getScreening()]);
      setWatchlist(list);
      const map = {};
      screening.coins.forEach((c) => {
        map[c.id] = c;
      });
      setScores(map);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const handleRemove = async (coinId) => {
    await removeFromWatchlist(coinId);
    load();
  };

  return (
    <div>
      <h1 className="text-xl font-bold text-terminal-text mb-1">Watchlist</h1>
      <p className="text-xs text-terminal-muted mb-4">
        Koin favorit Anda. Notifikasi browser akan muncul saat skor melewati threshold alert masing-masing koin.
      </p>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg overflow-hidden">
        {loading ? (
          <TableSkeleton rows={4} />
        ) : watchlist.length === 0 ? (
          <div className="text-center py-16 text-terminal-muted text-sm">
            Watchlist masih kosong. Klik ikon ☆ di dashboard untuk menambahkan koin.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-terminal-muted border-b border-terminal-border uppercase text-[11px] tracking-wider">
                <th className="px-4 py-3 font-medium">Koin</th>
                <th className="px-2 py-3 font-medium text-right">Harga</th>
                <th className="px-2 py-3 font-medium text-right">24h</th>
                <th className="px-2 py-3 font-medium text-right">Skor</th>
                <th className="px-2 py-3 font-medium text-right">Alert &gt;</th>
                <th className="px-2 py-3 font-medium text-center">Aksi</th>
              </tr>
            </thead>
            <tbody>
              {watchlist.map((w) => {
                const s = scores[w.coin_id];
                return (
                  <tr
                    key={w.coin_id}
                    className="border-b border-terminal-border/50 hover:bg-white/5 cursor-pointer"
                    onClick={() => navigate(`/coin/${w.coin_id}`)}
                  >
                    <td className="px-4 py-3 font-semibold">{w.symbol}</td>
                    <td className="px-2 py-3 text-right font-mono">{s ? formatPrice(s.price) : '-'}</td>
                    <td className={`px-2 py-3 text-right font-mono ${s ? changeColor(s.change24h) : ''}`}>
                      {s ? formatPercent(s.change24h) : '-'}
                    </td>
                    <td className="px-2 py-3 text-right">{s ? <ScoreBadge score={s.score} /> : '-'}</td>
                    <td className="px-2 py-3 text-right font-mono text-terminal-muted">{w.alert_threshold}</td>
                    <td className="px-2 py-3 text-center">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleRemove(w.coin_id);
                        }}
                        className="text-terminal-red text-xs hover:underline"
                      >
                        Hapus
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
