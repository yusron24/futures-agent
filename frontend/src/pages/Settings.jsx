import { useEffect, useState } from 'react';
import { getHealth } from '../api/client';

export default function Settings() {
  const [health, setHealth] = useState(null);
  const [notifPermission, setNotifPermission] = useState(
    'Notification' in window ? Notification.permission : 'unsupported'
  );

  useEffect(() => {
    getHealth()
      .then(setHealth)
      .catch(() => setHealth(null));
  }, []);

  const requestNotifPermission = async () => {
    if (!('Notification' in window)) return;
    const perm = await Notification.requestPermission();
    setNotifPermission(perm);
  };

  return (
    <div className="max-w-2xl">
      <h1 className="text-xl font-bold text-terminal-text mb-1">Pengaturan</h1>
      <p className="text-xs text-terminal-muted mb-6">
        API key untuk sumber data eksternal dikonfigurasi lewat file <code>.env</code> di server backend (bukan lewat
        browser), agar key tidak pernah terekspos ke client. Halaman ini menampilkan status konfigurasi saat ini.
      </p>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg p-5 space-y-4">
        <StatusRow
          label="Backend"
          ok={Boolean(health)}
          value={health ? 'Terhubung' : 'Tidak terhubung'}
        />
        <StatusRow
          label="CoinGecko API Key (opsional)"
          ok={health?.coingeckoApiKeyConfigured}
          value={health?.coingeckoApiKeyConfigured ? 'Dikonfigurasi' : 'Menggunakan tier gratis (tanpa key)'}
        />
        <StatusRow
          label="Data Sosial (LunarCrush/Santiment)"
          ok={health?.socialDataConfigured}
          value={health?.socialDataConfigured ? 'Aktif' : 'Belum dikonfigurasi (skor sosial memakai nilai netral placeholder)'}
        />
        <StatusRow
          label="Interval Scan Otomatis"
          ok
          value={health ? `${health.scanIntervalMinutes} menit` : '-'}
        />
        <StatusRow
          label="Threshold Sinyal"
          ok
          value={health ? `Skor ≥ ${health.signalThreshold}` : '-'}
        />
        <StatusRow
          label="Koin dianalisis detail / siklus"
          ok
          value={health ? `${health.detailedCoinsLimit} koin (dibatasi untuk menghindari rate limit CoinGecko)` : '-'}
        />
      </div>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg p-5 mt-4">
        <div className="text-sm font-semibold mb-2">Notifikasi Browser</div>
        <p className="text-xs text-terminal-muted mb-3">
          Izinkan notifikasi agar mendapat peringatan saat koin di watchlist Anda melewati skor threshold.
        </p>
        <div className="flex items-center gap-3">
          <span className="text-xs text-terminal-muted">Status: <b className="text-terminal-text">{notifPermission}</b></span>
          {notifPermission !== 'granted' && notifPermission !== 'unsupported' && (
            <button
              onClick={requestNotifPermission}
              className="px-3 py-1.5 text-xs font-semibold rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/40 hover:bg-terminal-accent/25"
            >
              Izinkan Notifikasi
            </button>
          )}
        </div>
      </div>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg p-5 mt-4 text-xs text-terminal-muted leading-relaxed">
        Untuk mengubah API key, edit file <code className="text-terminal-accent">backend/.env</code>:
        <pre className="mt-2 p-3 bg-terminal-bg rounded border border-terminal-border overflow-x-auto">
{`COINGECKO_API_URL=https://api.coingecko.com/api/v3
COINGECKO_API_KEY=
LUNARCRUSH_API_KEY=
SANTIMENT_API_KEY=`}
        </pre>
        Lalu restart backend (<code>npm run dev</code>) agar perubahan berlaku.
      </div>
    </div>
  );
}

function StatusRow({ label, ok, value }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-terminal-muted">{label}</span>
      <span className="flex items-center gap-2">
        <span className={`w-2 h-2 rounded-full ${ok ? 'bg-terminal-green' : 'bg-terminal-amber'}`} />
        <span className="text-terminal-text">{value}</span>
      </span>
    </div>
  );
}
