import { useNavigate } from 'react-router-dom';
import ScoreBadge from './ScoreBadge';
import CoinAvatar from './CoinAvatar';
import { formatPrice, formatPercent, formatCompact, changeColor } from '../utils/format';

export default function CoinTable({ coins, watchlistIds = new Set(), onToggleWatchlist }) {
  const navigate = useNavigate();

  if (!coins.length) {
    return (
      <div className="text-center py-16 text-terminal-muted text-sm">
        Tidak ada koin yang cocok dengan filter saat ini.
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-terminal-muted border-b border-terminal-border uppercase text-[11px] tracking-wider">
            <th className="px-4 py-3 font-medium">#</th>
            <th className="px-2 py-3 font-medium">Pair</th>
            <th className="px-2 py-3 font-medium text-right">Harga</th>
            <th className="px-2 py-3 font-medium text-right">24h</th>
            <th className="px-2 py-3 font-medium text-right">Vol Spike</th>
            <th className="px-2 py-3 font-medium text-right">RSI</th>
            <th className="px-2 py-3 font-medium text-right">Skor</th>
            <th className="px-2 py-3 font-medium text-center">☆</th>
          </tr>
        </thead>
        <tbody>
          {coins.map((coin, idx) => (
            <tr
              key={coin.id}
              onClick={() => navigate(`/coin/${coin.id}`)}
              className="border-b border-terminal-border/50 hover:bg-white/5 cursor-pointer animate-fade-in transition-colors"
            >
              <td className="px-4 py-3 text-terminal-muted">{coin.volumeRank ?? idx + 1}</td>
              <td className="px-2 py-3">
                <div className="flex items-center gap-2">
                  <CoinAvatar symbol={coin.symbol} />
                  <span className="font-semibold text-terminal-text">{coin.symbol}</span>
                  {coin.isNew && (
                    <span className="text-[9px] px-1.5 py-0.5 rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/30">
                      NEW
                    </span>
                  )}
                </div>
              </td>
              <td className="px-2 py-3 text-right font-mono">{formatPrice(coin.price)}</td>
              <td className={`px-2 py-3 text-right font-mono ${changeColor(coin.change24h)}`}>
                {formatPercent(coin.change24h)}
              </td>
              <td className="px-2 py-3 text-right font-mono text-terminal-text">
                {coin.volumeRatio != null ? `${coin.volumeRatio.toFixed(2)}x` : '-'}
                <div className="text-[10px] text-terminal-muted">{formatCompact(coin.volume24h)}</div>
              </td>
              <td className="px-2 py-3 text-right font-mono">
                {coin.rsi != null ? coin.rsi.toFixed(0) : '-'}
              </td>
              <td className="px-2 py-3 text-right">
                <ScoreBadge score={coin.score} />
              </td>
              <td className="px-2 py-3 text-center">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onToggleWatchlist?.(coin);
                  }}
                  className={`text-lg leading-none transition-colors ${
                    watchlistIds.has(coin.id) ? 'text-terminal-amber' : 'text-terminal-muted hover:text-terminal-amber'
                  }`}
                >
                  {watchlistIds.has(coin.id) ? '★' : '☆'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
