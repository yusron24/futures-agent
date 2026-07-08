export default function FilterBar({ filters, onChange, categories, onRefresh, loading, autoRefresh, onToggleAutoRefresh }) {
  const set = (patch) => onChange({ ...filters, ...patch });

  return (
    <div className="flex flex-wrap items-center gap-3 p-4 bg-terminal-panel border border-terminal-border rounded-lg mb-4">
      <div className="flex items-center gap-2">
        <label className="text-xs text-terminal-muted">Min Market Cap</label>
        <select
          value={filters.minMarketCap}
          onChange={(e) => set({ minMarketCap: e.target.value })}
          className="bg-terminal-bg border border-terminal-border rounded px-2 py-1.5 text-xs text-terminal-text"
        >
          <option value="0">Semua</option>
          <option value="10000000">≥ $10M</option>
          <option value="50000000">≥ $50M</option>
          <option value="100000000">≥ $100M</option>
          <option value="500000000">≥ $500M</option>
          <option value="1000000000">≥ $1B</option>
        </select>
      </div>

      <div className="flex items-center gap-2">
        <label className="text-xs text-terminal-muted">Kategori</label>
        <select
          value={filters.category}
          onChange={(e) => set({ category: e.target.value })}
          className="bg-terminal-bg border border-terminal-border rounded px-2 py-1.5 text-xs text-terminal-text max-w-[160px]"
        >
          <option value="">Semua Kategori</option>
          {categories.map((c) => (
            <option key={c.category_id} value={c.category_id}>
              {c.name}
            </option>
          ))}
        </select>
      </div>

      <label className="flex items-center gap-2 text-xs text-terminal-muted cursor-pointer">
        <input
          type="checkbox"
          checked={filters.newOnly}
          onChange={(e) => set({ newOnly: e.target.checked })}
          className="accent-terminal-accent"
        />
        Baru listing (&lt;30 hari)
      </label>

      <div className="ml-auto flex items-center gap-3">
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
          className="px-3 py-1.5 text-xs font-semibold rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/40 hover:bg-terminal-accent/25 disabled:opacity-50 transition-colors"
        >
          {loading ? 'Memuat...' : '⟳ Refresh Data'}
        </button>
      </div>
    </div>
  );
}
