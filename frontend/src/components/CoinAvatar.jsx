function hashHue(str) {
  let h = 0;
  for (let i = 0; i < str.length; i += 1) h = (h * 31 + str.charCodeAt(i)) % 360;
  return h;
}

/** Binance has no coin logos, so we render a deterministic colored initials badge instead. */
export default function CoinAvatar({ symbol, size = 'sm' }) {
  const label = (symbol || '?').slice(0, 3);
  const hue = hashHue(symbol || '?');
  const dimension = size === 'lg' ? 'w-10 h-10 text-sm' : 'w-5 h-5 text-[8px]';

  return (
    <span
      className={`inline-flex items-center justify-center rounded-full font-bold text-white shrink-0 ${dimension}`}
      style={{ backgroundColor: `hsl(${hue}, 55%, 38%)` }}
    >
      {label}
    </span>
  );
}
