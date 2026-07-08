import { NavLink } from 'react-router-dom';

const links = [
  { to: '/', label: 'Dashboard', icon: '📊' },
  { to: '/rsi-screener', label: 'RSI Screener', icon: '🎯' },
  { to: '/watchlist', label: 'Watchlist', icon: '⭐' },
  { to: '/signals', label: 'Riwayat Sinyal', icon: '🔔' },
  { to: '/settings', label: 'Pengaturan', icon: '⚙️' },
];

/**
 * Desktop (md+): always-visible static sidebar.
 * Mobile: slide-in drawer with a backdrop, opened from the top bar's
 * hamburger button and closed on backdrop tap or navigation.
 */
export default function Sidebar({ open, onClose }) {
  return (
    <>
      {open && (
        <div
          className="fixed inset-0 bg-black/60 z-30 md:hidden"
          onClick={onClose}
          aria-hidden="true"
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-40 w-64 max-w-[80vw] transform transition-transform duration-200 ease-out
          md:static md:z-auto md:w-56 md:max-w-none md:translate-x-0 md:transition-none
          shrink-0 border-r border-terminal-border bg-terminal-panel flex flex-col
          ${open ? 'translate-x-0' : '-translate-x-full'}`}
      >
        <div className="px-4 py-5 border-b border-terminal-border flex items-center justify-between">
          <div>
            <div className="text-terminal-accent font-bold tracking-widest text-sm">ALTCOIN</div>
            <div className="text-terminal-muted text-xs tracking-widest">SCREENER v1</div>
          </div>
          <button
            onClick={onClose}
            aria-label="Tutup menu"
            className="md:hidden text-terminal-muted text-xl leading-none px-1"
          >
            ✕
          </button>
        </div>
        <nav className="flex-1 py-3 overflow-y-auto">
          {links.map((link) => (
            <NavLink
              key={link.to}
              to={link.to}
              end={link.to === '/'}
              onClick={onClose}
              className={({ isActive }) =>
                `flex items-center gap-3 px-4 py-3 md:py-2.5 text-sm transition-colors ${
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
          Data: Binance Futures API · Not financial advice
        </div>
      </aside>
    </>
  );
}
