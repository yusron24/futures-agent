import { useCallback, useEffect, useState } from 'react';
import FilterBar from '../components/FilterBar';
import CoinTable from '../components/CoinTable';
import { TableSkeleton } from '../components/Skeleton';
import { getScreening, getWatchlist, addToWatchlist, removeFromWatchlist } from '../api/client';
import { getSocket } from '../api/socket';
import useInterval from '../hooks/useInterval';
import { timeAgo } from '../utils/format';

const DEFAULT_FILTERS = { minVolume24h: '0', newOnly: false };
const POLL_MS = 30000;

export default function Dashboard() {
  const [coins, setCoins] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [updatedAt, setUpdatedAt] = useState(null);
  const [filters, setFilters] = useState(DEFAULT_FILTERS);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [watchlistIds, setWatchlistIds] = useState(new Set());

  const loadWatchlist = useCallback(async () => {
    try {
      const list = await getWatchlist();
      setWatchlistIds(new Set(list.map((w) => w.coin_id)));
    } catch (err) {
      console.error('Failed to load watchlist', err);
    }
  }, []);

  // `silent` skips the loading state so background polls / websocket pushes
  // update the table in place without flashing skeletons or disabling buttons.
  const loadScreening = useCallback(
    async (opts = {}) => {
      if (!opts.silent) setLoading(true);
      try {
        const params = {};
        if (filters.minVolume24h && filters.minVolume24h !== '0') params.minVolume24h = filters.minVolume24h;
        if (filters.newOnly) params.newOnly = 'true';
        if (opts.forceRefresh) params.refresh = 'true';

        const data = await getScreening(params);
        setCoins(data.coins);
        setUpdatedAt(data.updatedAt);
        setError(null);
      } catch (err) {
        console.error(err);
        if (!opts.silent) {
          setError(
            err.response?.data?.error ||
              'Gagal memuat data screening. Binance mungkin sedang membatasi rate limit, coba lagi sebentar lagi.'
          );
        }
      } finally {
        if (!opts.silent) setLoading(false);
      }
    },
    [filters]
  );

  useEffect(() => {
    loadWatchlist();
  }, [loadWatchlist]);

  useEffect(() => {
    loadScreening();
  }, [loadScreening]);

  useEffect(() => {
    const socket = getSocket();
    const handleUpdate = () => loadScreening({ silent: true });
    socket.on('screening:update', handleUpdate);
    return () => socket.off('screening:update', handleUpdate);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  useInterval(() => {
    if (autoRefresh) loadScreening({ silent: true });
  }, autoRefresh ? POLL_MS : null);

  const handleToggleWatchlist = async (coin) => {
    try {
      if (watchlistIds.has(coin.id)) {
        await removeFromWatchlist(coin.id);
      } else {
        await addToWatchlist(coin);
      }
      loadWatchlist();
    } catch (err) {
      console.error('Failed to toggle watchlist', err);
    }
  };

  return (
    <div>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-1 mb-4">
        <div>
          <h1 className="text-lg sm:text-xl font-bold text-terminal-text">Dashboard Screening</h1>
          <p className="text-xs text-terminal-muted mt-0.5">
            {updatedAt ? `Update terakhir: ${timeAgo(updatedAt)}` : 'Memuat data awal...'}
          </p>
        </div>
        <div className="text-xs text-terminal-muted sm:text-right">
          {coins.length} pair dianalisis (Binance USDT-M Futures)
        </div>
      </div>

      <FilterBar
        filters={filters}
        onChange={setFilters}
        onRefresh={() => loadScreening({ forceRefresh: true })}
        loading={loading}
        autoRefresh={autoRefresh}
        onToggleAutoRefresh={() => setAutoRefresh((v) => !v)}
      />

      {error && (
        <div className="mb-4 px-4 py-3 rounded bg-terminal-red/10 border border-terminal-red/30 text-terminal-red text-sm">
          {error}
        </div>
      )}

      <div className="bg-terminal-panel border border-terminal-border rounded-lg overflow-hidden">
        {loading && coins.length === 0 ? (
          <TableSkeleton />
        ) : (
          <CoinTable coins={coins} watchlistIds={watchlistIds} onToggleWatchlist={handleToggleWatchlist} />
        )}
      </div>
    </div>
  );
}
