import { NavLink } from 'react-router-dom';

const links = [
  { to: '/', label: 'Dashboard', icon: '📊' },
  { to: '/rsi-screener', label: 'RSI Screener', icon: '🎯' },
  { to: '/watchlist', label: 'Watchlist', icon: '⭐' },
  { to: '/signals', label: 'Riwayat Sinyal', icon: '🔔' },
  { to: '/settings', label: 'Pengaturan', icon: '⚙️' },
];

export default function Sidebar() {
  return (
    <aside className="w-56 shrink-0 border-r border-terminal-border bg-terminal-panel flex flex-col">
      <div className="px-4 py-5 border-b border-terminal-border">
        <div className="text-terminal-accent font-bold tracking-widest text-sm">ALTCOIN</div>
        <div className="text-terminal-muted text-xs tracking-widest">SCREENER v1</div>
      </div>
      <nav className="flex-1 py-3">
        {links.map((link) => (
          <NavLink
            key={link.to}
            to={link.to}
            end={link.to === '/'}
            className={({ isActive }) =>
              `flex items-center gap-3 px-4 py-2.5 text-sm transition-colors ${
                isActive
                  ? 'bg-terminal-accent/10 text-terminal-accent border-r-2 border-terminal-accent'
                  : 'text-terminal-muted hover:text-terminal-text hover:bg-white/5'
              }`
            }
          >
            <span>{link.icon}</span>
            <span>{link.label}</span>
          </NavLink>
        ))}
      </nav>
      <div className="px-4 py-3 border-t border-terminal-border text-[10px] text-terminal-muted">
        Data: CoinGecko API · Not financial advice
      </div>
    </aside>
  );
}
