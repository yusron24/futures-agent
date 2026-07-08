import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { formatPrice } from '../utils/format';

export default function PriceChart({ prices = [] }) {
  const data = prices.map(([ts, price]) => ({
    time: new Date(ts).toLocaleDateString('id-ID', { day: '2-digit', month: 'short' }),
    price,
  }));

  if (!data.length) {
    return <div className="h-64 flex items-center justify-center text-terminal-muted text-sm">Tidak ada data chart</div>;
  }

  const isUp = data[data.length - 1].price >= data[0].price;
  const strokeColor = isUp ? '#00e676' : '#ff4d5e';

  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="priceGradient" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor={strokeColor} stopOpacity={0.35} />
            <stop offset="95%" stopColor={strokeColor} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid stroke="#1c2432" strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="time" stroke="#5b6b82" fontSize={11} tickLine={false} axisLine={false} />
        <YAxis
          stroke="#5b6b82"
          fontSize={11}
          tickLine={false}
          axisLine={false}
          domain={['auto', 'auto']}
          tickFormatter={(v) => formatPrice(v)}
          width={80}
        />
        <Tooltip
          contentStyle={{ background: '#0f1520', border: '1px solid #1c2432', borderRadius: 8, fontSize: 12 }}
          labelStyle={{ color: '#5b6b82' }}
          formatter={(value) => [formatPrice(value), 'Harga']}
        />
        <Area type="monotone" dataKey="price" stroke={strokeColor} strokeWidth={2} fill="url(#priceGradient)" />
      </AreaChart>
    </ResponsiveContainer>
  );
}
