import { useEffect, useState } from 'react';
import { getSettings, updateSettings, testNotification } from '../api/client';

const EMPTY_FORM = {
  coingeckoApiKey: '',
  lunarcrushApiKey: '',
  cryptoquantApiKey: '',
  whaleAlertApiKey: '',
  scanIntervalMinutes: 5,
  signalScoreThreshold: 75,
  detailedCoinsLimit: 60,
  telegramBotToken: '',
  telegramChatId: '',
  telegramEnabled: false,
  discordWebhookUrl: '',
  discordEnabled: false,
};

export default function Settings() {
  const [form, setForm] = useState(EMPTY_FORM);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState(null);
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState(null);
  const [notifPermission, setNotifPermission] = useState(
    'Notification' in window ? Notification.permission : 'unsupported'
  );

  const load = () => {
    setLoading(true);
    getSettings()
      .then((s) =>
        setForm({
          coingeckoApiKey: s.coingeckoApiKey || '',
          lunarcrushApiKey: s.lunarcrushApiKey || '',
          cryptoquantApiKey: s.cryptoquantApiKey || '',
          whaleAlertApiKey: s.whaleAlertApiKey || '',
          scanIntervalMinutes: s.scanIntervalMinutes,
          signalScoreThreshold: s.signalScoreThreshold,
          detailedCoinsLimit: s.detailedCoinsLimit,
          telegramBotToken: s.telegramBotToken || '',
          telegramChatId: s.telegramChatId || '',
          telegramEnabled: Boolean(s.telegramEnabled),
          discordWebhookUrl: s.discordWebhookUrl || '',
          discordEnabled: Boolean(s.discordEnabled),
        })
      )
      .catch(() => setMessage({ type: 'error', text: 'Gagal memuat pengaturan dari backend.' }))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    setMessage(null);
    try {
      await updateSettings(form);
      setMessage({ type: 'success', text: 'Pengaturan disimpan dan langsung diterapkan (tanpa restart).' });
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'Gagal menyimpan pengaturan.' });
    } finally {
      setSaving(false);
    }
  };

  const handleTestNotification = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const data = await testNotification();
      setTestResult({ type: 'success', data: data.result });
    } catch (err) {
      setTestResult({ type: 'error', text: err.response?.data?.error || 'Gagal mengirim notifikasi uji coba.' });
    } finally {
      setTesting(false);
    }
  };

  const requestNotifPermission = async () => {
    if (!('Notification' in window)) return;
    const perm = await Notification.requestPermission();
    setNotifPermission(perm);
  };

  if (loading) {
    return <div className="text-terminal-muted text-sm">Memuat pengaturan...</div>;
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-xl font-bold text-terminal-text mb-1">Pengaturan</h1>
      <p className="text-xs text-terminal-muted mb-6">
        Diubah di sini langsung tersimpan di server (SQLite) dan diterapkan seketika — tidak perlu edit file{' '}
        <code>.env</code> atau restart backend.
      </p>

      <form onSubmit={handleSave} className="bg-terminal-panel border border-terminal-border rounded-lg p-5 space-y-4">
        <Field
          label="CoinGecko API Key (opsional)"
          hint="Kosongkan untuk pakai tier gratis tanpa key."
        >
          <input
            type="password"
            autoComplete="off"
            value={form.coingeckoApiKey}
            onChange={(e) => set({ coingeckoApiKey: e.target.value })}
            placeholder="CG-xxxxxxxxxxxxxxxx"
            className="input"
          />
        </Field>

        <Field
          label="LunarCrush API Key (opsional)"
          hint="Mengaktifkan skor momentum sosial. Kosong = pakai nilai netral placeholder."
        >
          <input
            type="password"
            autoComplete="off"
            value={form.lunarcrushApiKey}
            onChange={(e) => set({ lunarcrushApiKey: e.target.value })}
            placeholder="lc_xxxxxxxxxxxxxxxx"
            className="input"
          />
        </Field>

        <Field
          label="CryptoQuant API Key (opsional)"
          hint="Exchange inflow/outflow & supply-on-exchange untuk BTC/ETH (dipakai juga sebagai proxy makro untuk altcoin lain). Kosong = data dummy berlabel jelas."
        >
          <input
            type="password"
            autoComplete="off"
            value={form.cryptoquantApiKey}
            onChange={(e) => set({ cryptoquantApiKey: e.target.value })}
            placeholder="cq_xxxxxxxxxxxxxxxx"
            className="input"
          />
        </Field>

        <Field
          label="Whale Alert API Key (opsional)"
          hint="Jumlah transaksi whale >$100k (1 jam terakhir) per koin. Kosong = data dummy berlabel jelas."
        >
          <input
            type="password"
            autoComplete="off"
            value={form.whaleAlertApiKey}
            onChange={(e) => set({ whaleAlertApiKey: e.target.value })}
            placeholder="wa_xxxxxxxxxxxxxxxx"
            className="input"
          />
        </Field>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Field label="Interval Scan (menit)">
            <input
              type="number"
              min={1}
              max={120}
              value={form.scanIntervalMinutes}
              onChange={(e) => set({ scanIntervalMinutes: e.target.value })}
              className="input"
            />
          </Field>
          <Field label="Threshold Sinyal (0-100)">
            <input
              type="number"
              min={0}
              max={100}
              value={form.signalScoreThreshold}
              onChange={(e) => set({ signalScoreThreshold: e.target.value })}
              className="input"
            />
          </Field>
          <Field label="Koin Detail / Siklus">
            <input
              type="number"
              min={5}
              max={250}
              value={form.detailedCoinsLimit}
              onChange={(e) => set({ detailedCoinsLimit: e.target.value })}
              className="input"
            />
          </Field>
        </div>

        <hr className="border-terminal-border" />
        <div className="text-sm font-semibold text-terminal-text">Notifikasi Telegram &amp; Discord</div>
        <p className="text-xs text-terminal-muted -mt-2">
          Dikirim otomatis saat koin di watchlist melewati threshold, atau saat ada sinyal "Potensi Pergerakan
          Besar" baru.
        </p>

        <div className="space-y-3 bg-terminal-bg border border-terminal-border rounded-lg p-4">
          <ToggleField
            label="Aktifkan Telegram"
            checked={form.telegramEnabled}
            onChange={(v) => set({ telegramEnabled: v })}
          />
          <Field label="Bot Token" hint="Dapatkan dari @BotFather di Telegram.">
            <input
              type="password"
              autoComplete="off"
              value={form.telegramBotToken}
              onChange={(e) => set({ telegramBotToken: e.target.value })}
              placeholder="123456789:AAExxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
              className="input"
            />
          </Field>
          <Field label="Chat ID" hint="ID chat/grup tujuan pesan (boleh angka negatif untuk grup).">
            <input
              type="text"
              autoComplete="off"
              value={form.telegramChatId}
              onChange={(e) => set({ telegramChatId: e.target.value })}
              placeholder="123456789"
              className="input"
            />
          </Field>
        </div>

        <div className="space-y-3 bg-terminal-bg border border-terminal-border rounded-lg p-4">
          <ToggleField
            label="Aktifkan Discord"
            checked={form.discordEnabled}
            onChange={(v) => set({ discordEnabled: v })}
          />
          <Field label="Webhook URL" hint="Channel Settings → Integrations → Webhooks di Discord.">
            <input
              type="password"
              autoComplete="off"
              value={form.discordWebhookUrl}
              onChange={(e) => set({ discordWebhookUrl: e.target.value })}
              placeholder="https://discord.com/api/webhooks/..."
              className="input"
            />
          </Field>
        </div>

        {message && (
          <div
            className={`text-xs px-3 py-2 rounded border ${
              message.type === 'success'
                ? 'bg-terminal-green/10 border-terminal-green/30 text-terminal-green'
                : 'bg-terminal-red/10 border-terminal-red/30 text-terminal-red'
            }`}
          >
            {message.text}
          </div>
        )}

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={saving}
            className="px-4 py-2 text-sm font-semibold rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/40 hover:bg-terminal-accent/25 disabled:opacity-50 transition-colors"
          >
            {saving ? 'Menyimpan...' : 'Simpan Pengaturan'}
          </button>
          <button
            type="button"
            onClick={handleTestNotification}
            disabled={testing || (!form.telegramEnabled && !form.discordEnabled)}
            className="px-4 py-2 text-sm font-semibold rounded bg-terminal-amber/15 text-terminal-amber border border-terminal-amber/40 hover:bg-terminal-amber/25 disabled:opacity-40 transition-colors"
          >
            {testing ? 'Mengirim...' : 'Kirim Notifikasi Uji Coba'}
          </button>
        </div>

        {testResult && (
          <div
            className={`text-xs px-3 py-2 rounded border ${
              testResult.type === 'error'
                ? 'bg-terminal-red/10 border-terminal-red/30 text-terminal-red'
                : 'bg-terminal-panel border-terminal-border text-terminal-text'
            }`}
          >
            {testResult.type === 'error' ? (
              testResult.text
            ) : (
              <div className="space-y-1">
                <ChannelResult label="Telegram" result={testResult.data.telegram} />
                <ChannelResult label="Discord" result={testResult.data.discord} />
              </div>
            )}
          </div>
        )}
      </form>

      <div className="bg-terminal-panel border border-terminal-border rounded-lg p-5 mt-4">
        <div className="text-sm font-semibold mb-2">Notifikasi Browser</div>
        <p className="text-xs text-terminal-muted mb-3">
          Izinkan notifikasi agar mendapat peringatan saat koin di watchlist Anda melewati skor threshold.
        </p>
        <div className="flex items-center gap-3">
          <span className="text-xs text-terminal-muted">
            Status: <b className="text-terminal-text">{notifPermission}</b>
          </span>
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
    </div>
  );
}

function Field({ label, hint, children }) {
  return (
    <label className="block">
      <span className="block text-xs text-terminal-muted mb-1">{label}</span>
      {children}
      {hint && <span className="block text-[10px] text-terminal-muted mt-1">{hint}</span>}
    </label>
  );
}

function ToggleField({ label, checked, onChange }) {
  return (
    <label className="flex items-center gap-2 text-xs text-terminal-text cursor-pointer">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="accent-terminal-accent"
      />
      {label}
    </label>
  );
}

function ChannelResult({ label, result }) {
  if (!result || result.skipped) {
    return (
      <div className="text-terminal-muted">
        {label}: <span>dilewati (belum aktif/dikonfigurasi)</span>
      </div>
    );
  }
  return (
    <div className={result.success ? 'text-terminal-green' : 'text-terminal-red'}>
      {label}: {result.success ? 'terkirim ✓' : `gagal — ${result.error}`}
    </div>
  );
}
