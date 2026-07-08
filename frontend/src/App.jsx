import { useState } from 'react';
import { Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import NotificationManager from './components/NotificationManager';
import Dashboard from './pages/Dashboard';
import CoinDetail from './pages/CoinDetail';
import RsiScreener from './pages/RsiScreener';
import Watchlist from './pages/Watchlist';
import SignalHistory from './pages/SignalHistory';
import Settings from './pages/Settings';

export default function App() {
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="flex h-dvh bg-terminal-bg text-terminal-text overflow-hidden">
      <NotificationManager />
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <div className="flex-1 flex flex-col min-w-0">
        {/* Mobile top bar - hidden on desktop where the sidebar is always visible */}
        <header className="md:hidden flex items-center gap-3 px-4 py-3 border-b border-terminal-border bg-terminal-panel shrink-0">
          <button
            onClick={() => setSidebarOpen(true)}
            aria-label="Buka menu"
            className="text-terminal-text text-xl leading-none px-1"
          >
            ☰
          </button>
          <div className="text-terminal-accent font-bold tracking-widest text-sm">
            ALTCOIN <span className="text-terminal-muted font-normal">SCREENER</span>
          </div>
        </header>

        <main className="flex-1 overflow-y-auto p-4 sm:p-6">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/coin/:id" element={<CoinDetail />} />
            <Route path="/rsi-screener" element={<RsiScreener />} />
            <Route path="/watchlist" element={<Watchlist />} />
            <Route path="/signals" element={<SignalHistory />} />
            <Route path="/settings" element={<Settings />} />
          </Routes>
        </main>
      </div>
    </div>
  );
}
