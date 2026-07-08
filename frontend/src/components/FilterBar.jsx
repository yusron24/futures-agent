export default function FilterBar({ filters, onChange, onRefresh, loading, autoRefresh, onToggleAutoRefresh }) {
  const set = (patch) => onChange({ ...filters, ...patch });

  return (
    <div className="flex flex-col sm:flex-row sm:flex-wrap sm:items-center gap-3 p-3 sm:p-4 bg-terminal-panel border border-terminal-border rounded-lg mb-4">
      <div className="flex items-center justify-between sm:justify-start gap-2">
        <label className="text-xs text-terminal-muted whitespace-nowrap">Min Volume 24h</label>
        <select
          value={filters.minVolume24h}
          onChange={(e) => set({ minVolume24h: e.target.value })}
          className="bg-terminal-bg border border-terminal-border rounded px-2 py-1.5 text-xs text-terminal-text"
        >
          <option value="0">Semua</option>
          <option value="1000000">≥ $1Jt</option>
          <option value="10000000">≥ $10Jt</option>
          <option value="50000000">≥ $50Jt</option>
          <option value="100000000">≥ $100Jt</option>
          <option value="500000000">≥ $500Jt</option>
        </select>
      </div>

      <label className="flex items-center gap-2 text-xs text-terminal-muted cursor-pointer">
        <input
          type="checkbox"
          checked={filters.newOnly}
          onChange={(e) => set({ newOnly: e.target.checked })}
          className="accent-terminal-accent"
        />
        Baru listing di Binance (&lt;30 hari)
      </label>

      <div className="flex items-center justify-between sm:justify-end gap-3 sm:ml-auto">
        <label className="flex items-center gap-2 text-xs text-terminal-muted cursor-pointer">
          <input
            type="checkbox"
            checked={autoRefresh}
            onChange={onToggleAutoRefresh}
            className="accent-terminal-accent"
          />
          Auto-refresh 30s
        </label>
        <button
          onClick={onRefresh}
          disabled={loading}
          className="px-3 py-1.5 text-xs font-semibold rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/40 hover:bg-terminal-accent/25 disabled:opacity-50 transition-colors whitespace-nowrap"
        >
          {loading ? 'Memuat...' : '⟳ Refresh'}
        </button>
      </div>
    </div>
  );
}
