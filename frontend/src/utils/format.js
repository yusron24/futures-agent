export function formatPrice(price) {
  if (price == null) return '-';
  if (price >= 1) return `$${price.toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
  if (price >= 0.01) return `$${price.toFixed(4)}`;
  return `$${price.toPrecision(4)}`;
}

export function formatCompact(num) {
  if (num == null) return '-';
  return new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 2 }).format(num);
}

export function formatUsdCompact(num) {
  if (num == null) return '-';
  const sign = num < 0 ? '-' : '';
  return `${sign}$${formatCompact(Math.abs(num))}`;
}

export function formatPercent(value) {
  if (value == null) return '-';
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

export function changeColor(value) {
  if (value == null) return 'text-terminal-muted';
  return value >= 0 ? 'text-terminal-green' : 'text-terminal-red';
}

export function scoreColor(score) {
  if (score >= 75) return 'text-terminal-green';
  if (score >= 50) return 'text-terminal-amber';
  return 'text-terminal-muted';
}

export function timeAgo(iso) {
  if (!iso) return '-';
  const diff = Date.now() - new Date(iso).getTime();
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return `${seconds}s lalu`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m lalu`;
  const hours = Math.floor(minutes / 60);
  return `${hours}j lalu`;
}
