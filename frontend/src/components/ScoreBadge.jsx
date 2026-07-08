export default function ScoreBadge({ score, size = 'md' }) {
  const color =
    score >= 75
      ? 'bg-terminal-green/15 text-terminal-green border-terminal-green/40'
      : score >= 50
      ? 'bg-terminal-amber/15 text-terminal-amber border-terminal-amber/40'
      : 'bg-terminal-muted/10 text-terminal-muted border-terminal-muted/30';

  const sizeClasses = size === 'lg' ? 'text-lg px-3 py-1' : 'text-xs px-2 py-0.5';

  return (
    <span className={`inline-flex items-center justify-center rounded border font-bold ${color} ${sizeClasses}`}>
      {Math.round(score)}
    </span>
  );
}

export function BigMoveBadge() {
  return (
    <span className="inline-flex items-center gap-1 rounded bg-terminal-green/15 border border-terminal-green/40 text-terminal-green text-xs font-bold px-2 py-1 animate-pulse-fast">
      🚀 Potensi Pergerakan Besar
    </span>
  );
}
