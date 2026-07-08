import { Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import NotificationManager from './components/NotificationManager';
import Dashboard from './pages/Dashboard';
import CoinDetail from './pages/CoinDetail';
import Watchlist from './pages/Watchlist';
import SignalHistory from './pages/SignalHistory';
import Settings from './pages/Settings';

export default function App() {
  return (
    <div className="flex h-screen bg-terminal-bg text-terminal-text">
      <NotificationManager />
      <Sidebar />
      <main className="flex-1 overflow-y-auto p-6">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/coin/:id" element={<CoinDetail />} />
          <Route path="/watchlist" element={<Watchlist />} />
          <Route path="/signals" element={<SignalHistory />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </main>
    </div>
  );
}
