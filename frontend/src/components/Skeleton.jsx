export function TableSkeleton({ rows = 10 }) {
  return (
    <div className="w-full">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 py-3 border-b border-terminal-border/60">
          <div className="skeleton h-4 w-4 rounded-full" />
          <div className="skeleton h-4 w-24" />
          <div className="skeleton h-4 w-16 ml-auto" />
          <div className="skeleton h-4 w-14" />
          <div className="skeleton h-4 w-14" />
          <div className="skeleton h-4 w-10" />
          <div className="skeleton h-4 w-10" />
        </div>
      ))}
    </div>
  );
}

export function CardSkeleton() {
  return (
    <div className="p-4 space-y-3">
      <div className="skeleton h-6 w-40" />
      <div className="skeleton h-48 w-full" />
      <div className="skeleton h-4 w-full" />
      <div className="skeleton h-4 w-2/3" />
    </div>
  );
}
