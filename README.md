# Altcoin Screener

Aplikasi full-stack untuk mendeteksi dan menyaring altcoin dengan potensi pergerakan harga besar, menggunakan data publik **Binance USDT-M Futures**. Backend Express + SQLite + Socket.IO, frontend React (Vite) + Tailwind CSS dengan tema gelap ala terminal trading.

## Struktur Proyek

```
backend/    Express API, scoring engine, scheduler (cron), SQLite (watchlist + riwayat sinyal)
frontend/   React (Vite) + Tailwind + Recharts, dashboard screening real-time
```

## Prasyarat

- **Node.js >= 22.5** (backend memakai modul bawaan `node:sqlite`, jadi tidak ada dependency native yang perlu dikompilasi — aman dijalankan di Termux/Android, Windows, macOS, atau Linux apa pun tanpa perlu toolchain build/NDK).

## Cara Menjalankan

### 1. Backend

```bash
cd backend
cp .env.example .env   # defaultnya sudah bisa langsung jalan, tidak perlu API key
npm install
npm run dev             # nodemon, restart otomatis saat kode berubah
# atau: npm start
```

Server berjalan di `http://localhost:5000`. Database SQLite (`backend/data/screener.db`) dibuat otomatis saat pertama kali dijalankan.

### 2. Frontend

Di terminal terpisah:

```bash
cd frontend
cp .env.example .env    # VITE_API_URL default sudah mengarah ke localhost:5000
npm install
npm run dev
```

Buka `http://localhost:5173` di browser.

> Pastikan backend sudah berjalan lebih dulu agar dashboard bisa mengambil data.

## Sumber Data: Binance USDT-M Futures

Aplikasi ini mengambil data langsung dari **Binance Futures API publik** (`fapi.binance.com`) — tidak perlu API key untuk data pasar (harga, volume, kline), dan rate limit-nya jauh lebih longgar dibanding CoinGecko free tier (2400 weight/menit vs realistanya cuma 5-15 request/menit di CoinGecko). Konsekuensinya, "universe" screening di sini adalah **pair USDT-M perpetual yang terdaftar di Binance Futures** (sekitar 300+ pair), bukan seluruh pasar kripto global. Beberapa fitur yang sebelumnya ada dari CoinGecko sengaja dihapus karena Binance tidak menyediakannya:

- ❌ Market cap & ranking market cap — diganti **ranking berdasarkan volume 24h** (proxy ukuran/likuiditas terdekat yang tersedia).
- ❌ Kategori/sektor (DeFi, Layer 1, Meme, dll) — filter kategori dihapus dari Dashboard.
- ❌ Logo, deskripsi, ATH/ATL koin — logo diganti avatar inisial berwarna otomatis; deskripsi & ATH/ATL tidak ditampilkan.
- ❌ Perubahan harga 1 jam — Binance tidak menyediakannya di endpoint ticker tanpa request tambahan per pair, jadi momentum sekarang dihitung dari perubahan 24h + 7d saja (7d dihitung gratis dari kline harian yang sudah diambil untuk RSI/MACD, tanpa request tambahan).
- ✅ Deteksi "baru listing" jadi **lebih akurat** — pakai field `onboardDate` asli dari Binance, bukan lagi heuristik tanggal all-time-low seperti versi CoinGecko.
- ✅ Karena rate limit Binance jauh lebih longgar, **seluruh universe screening** (bukan cuma subset ~30 koin) mendapat analisis penuh (RSI/MACD/volume-spike) setiap siklus.

## Konfigurasi (.env backend)

`.env` hanya dipakai sebagai **nilai default awal**. Setelah backend jalan, buka halaman **Pengaturan** di `http://localhost:5173/settings` untuk mengubah interval scan, threshold sinyal, ukuran universe screening, dan API key opsional langsung dari browser — tersimpan di SQLite dan diterapkan seketika tanpa perlu edit `.env` atau restart backend.

| Variable | Keterangan |
|---|---|
| `PORT` | Port backend (default 5000) |
| `BINANCE_FUTURES_API_URL` | Base URL Binance Futures API (default `https://fapi.binance.com`) |
| `BINANCE_FETCH_DELAY_MS` | Jeda awal (ms) antar-request ke Binance, auto-adaptif (lihat bawah) — default 120 |
| `LUNARCRUSH_API_KEY` / `SOCIAL_API_KEY` | Opsional, mengaktifkan skor momentum sosial. Tanpa key, skor sosial memakai nilai netral placeholder — bisa juga diisi lewat halaman Pengaturan |
| `CRYPTOQUANT_API_KEY` | Opsional, exchange inflow/outflow & supply-on-exchange (BTC/ETH; dipakai sebagai proxy makro untuk altcoin lain) — bisa juga diisi lewat halaman Pengaturan |
| `WHALE_ALERT_API_KEY` | Opsional, jumlah transaksi whale >$100k (1 jam terakhir) per koin dari [Whale Alert](https://whale-alert.io) — bisa juga diisi lewat halaman Pengaturan |
| `GLASSNODE_API_KEY` | Dicadangkan untuk pengembangan berikutnya (belum tersambung ke endpoint live) |
| `DETAILED_COINS_LIMIT` | Jumlah pair Binance teratas (berdasarkan volume 24h) yang jadi universe screening, default 150, maksimal 300 — semuanya dianalisis penuh setiap siklus — bisa diubah lewat halaman Pengaturan |
| `SCAN_INTERVAL_MINUTES` | Interval scheduler penghitungan ulang skor (default 5 menit) — bisa diubah lewat halaman Pengaturan |
| `SIGNAL_SCORE_THRESHOLD` | Skor minimum agar sebuah koin dicatat sebagai "sinyal" ke riwayat (default 75) — bisa diubah lewat halaman Pengaturan |
| `CORS_ORIGIN` | Origin frontend yang diizinkan (default `http://localhost:5173`) |
| `FRONTEND_URL` | URL publik frontend, dipakai untuk link "lihat detail" di notifikasi Telegram/Discord (default `http://localhost:5173`) |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` / `TELEGRAM_ENABLED` | Opsional, notifikasi Telegram — bisa juga diisi & di-toggle lewat halaman Pengaturan |
| `DISCORD_WEBHOOK_URL` / `DISCORD_ENABLED` | Opsional, notifikasi Discord — bisa juga diisi & di-toggle lewat halaman Pengaturan |
| `PROXY_URL` / `PROXY_ENABLED` | Opsional, proxy outbound untuk request ke Binance (format `http://user:pass@host:port`) — **jangan pernah commit nilai asli ke sini**, isi lewat `.env` lokal (sudah di-gitignore) atau halaman Pengaturan |

## Cara Kerja Screening

1. Setiap `SCAN_INTERVAL_MINUTES` menit, backend mengambil semua pair USDT-M perpetual `TRADING` dari `/fapi/v1/exchangeInfo` + `/fapi/v1/ticker/24hr` (1 request untuk seluruh pasar), lalu diurutkan berdasarkan volume 24h dan diambil `DETAILED_COINS_LIMIT` teratas — stablecoin (USDC, BUSD, dll) difilter otomatis.
2. **Setiap** pair di universe (bukan cuma subset) mendapat analisis penuh dari satu kali fetch kline harian (`/fapi/v1/klines`, 40 hari): RSI(14), MACD(12,26,9), rasio volume spike (volume hari ini vs rata-rata harian sebelumnya), dan perubahan 7 hari — semuanya diturunkan dari data yang sama, tanpa request tambahan per metrik.
3. Semua request ke Binance dipacing lewat **rate limiter adaptif** (`backend/utils/binanceClient.js`): mulai cepat (~120ms antar-request), otomatis melambat kalau kena 429/418 beruntun, lalu pelan-pelan mempercepat lagi setelah serangkaian request sukses. Kalau IP Anda tetap kena rate-limit/blokir (umum terjadi di IP mobile/shared/datacenter), aktifkan **Proxy Outbound** di halaman Pengaturan (lihat bawah) supaya semua request Binance dirutekan lewat proxy tersebut.
4. Skor potensi 0-100 dihitung dari kombinasi berbobot: Volume Spike 25%, Momentum Harga 20%, Volatilitas 10%, RSI 10%, Sosial 10%, On-Chain 25% (lihat bawah). Bobot metrik apa pun yang datanya tidak tersedia untuk koin tersebut dialihkan secara proporsional ke metrik lain, jadi totalnya selalu 100%.
5. Koin dengan skor ≥ threshold dicatat ke tabel `signals` di SQLite dan di-broadcast lewat WebSocket (`screening:update`, `signals:new`, `watchlist:alert`) agar dashboard & notifikasi browser update real-time.
6. Frontend melakukan polling setiap 30 detik (bisa dimatikan) dan juga mendengarkan event WebSocket untuk refresh instan.

### Analisis On-Chain

`backend/services/onchainService.js` menyediakan tiga metrik on-chain per koin, di-cache 5 menit:

- **Exchange inflow/outflow & % supply di exchange** — via CryptoQuant (`CRYPTOQUANT_API_KEY`), hanya tersedia untuk BTC & ETH secara langsung; altcoin lain memakai data BTC sebagai proxy makro (`isProxy: true` pada response).
- **Whale transaction count (>$100k)** — via [Whale Alert](https://whale-alert.io) (`WHALE_ALERT_API_KEY`), per-koin, jendela 1 jam terakhir (batasan tier gratis), diklasifikasikan sebagai deposit ke exchange (bearish) vs penarikan dari exchange (bullish).
- **Skor on-chain** = rata-rata dari *exchange outflow spike* (perubahan % supply di exchange) dan *whale accumulation* (net whale withdrawal - deposit), masing-masing bagian dari bobot On-Chain 25%.

Jika tidak ada API key CryptoQuant/Whale Alert yang dikonfigurasi (atau panggilan live gagal), service mengembalikan **data dummy deterministik** — angka berubah tiap 5 menit tapi stabil di jendela yang sama, dengan struktur field identik ke data asli sehingga tinggal diganti nanti. Data dummy ditampilkan di halaman detail koin dengan label jelas "DUMMY (contoh)" dan **tidak** ikut memengaruhi skor — bobot 25%-nya dialihkan proporsional ke metrik lain sampai data live tersedia.

### Notifikasi Telegram & Discord

`backend/services/notificationService.js` mengirim notifikasi otomatis setiap siklus screening saat:

- koin di **watchlist** mencapai skor ≥ threshold alert-nya masing-masing, atau
- koin apa pun mencapai skor ≥ `SIGNAL_SCORE_THRESHOLD` (sinyal "Potensi Pergerakan Besar" baru, dicatat ke `signals`).

Setiap koin hanya mengirim satu notifikasi per siklus meski memenuhi keduanya. Pesan berisi simbol, skor, perubahan harga 24h, volume spike, RSI, dan link ke halaman detail (`FRONTEND_URL`). Aktifkan dan isi kredensialnya lewat halaman **Pengaturan** (tersimpan di SQLite, langsung berlaku tanpa restart), lalu pakai tombol **Kirim Notifikasi Uji Coba** untuk memastikan token/webhook-nya valid — hasil per-channel (berhasil/gagal beserta alasannya) langsung ditampilkan.

**Cara mendapatkan Telegram Bot Token & Chat ID:**
1. Chat [@BotFather](https://t.me/BotFather) di Telegram, kirim `/newbot`, ikuti instruksinya → dapat **Bot Token** (format `123456789:AA...`).
2. Mulai chat dengan bot Anda (klik link yang diberikan BotFather) dan kirim pesan apa saja, atau tambahkan bot ke grup yang diinginkan.
3. Buka `https://api.telegram.org/bot<TOKEN>/getUpdates` di browser (ganti `<TOKEN>`), cari field `"chat":{"id": ...}` di hasil JSON-nya → itu **Chat ID** Anda (untuk grup, angkanya negatif).

**Cara mendapatkan Discord Webhook URL:**
1. Di server Discord Anda, buka **Server Settings → Integrations → Webhooks → New Webhook**.
2. Pilih channel tujuan, beri nama (opsional), lalu klik **Copy Webhook URL**.
3. Tempel URL tersebut di halaman Pengaturan.

Jika token/webhook salah atau ada masalah jaringan, error-nya di-catch dan dicatat di log backend (`[notification] Telegram/Discord send failed: ...`) tanpa menghentikan siklus screening atau mempengaruhi koin lain.

### Proxy Outbound (mengatasi rate limit / ban IP)

Kalau server Anda kena rate-limit atau diblokir Binance (sering terjadi di IP mobile, shared hosting, atau datacenter yang IP-nya dipakai banyak orang), aktifkan proxy lewat halaman **Pengaturan → Proxy Outbound**:

1. Isi **Proxy URL** dengan format `http://username:password@host:port`.
2. Centang **Aktifkan Proxy**, klik **Simpan Pengaturan** — berlaku langsung tanpa restart.

Semua request ke Binance (`backend/utils/binanceClient.js`) akan dirutekan lewat proxy tersebut menggunakan [`https-proxy-agent`](https://www.npmjs.com/package/https-proxy-agent). Kredensial proxy tersimpan **hanya di database SQLite lokal Anda** (`backend/data/screener.db`, sudah di-gitignore) — tidak pernah dikirim ke tempat lain atau ikut ter-commit ke git. Kalau Anda taruh proxy URL di `.env` sebagai gantinya, pastikan file `.env` itu memang tidak pernah di-commit (sudah di-gitignore secara default di repo ini) — jangan sekali-kali menempelkan kredensial proxy ke pesan commit, kode, atau tempat publik lainnya.

### RSI Screener

Halaman terpisah (`/rsi-screener`) yang menampilkan dua daftar: koin **oversold** (RSI < 30, secara historis berpotensi rebound) dan **overbought** (RSI > 70, berpotensi koreksi) — murni indikator teknikal, bukan sinyal beli/jual. Pilih timeframe RSI-14 lewat tombol di atas tabel: **15m, 1H, 4H, 1D, 1W**.

Endpoint-nya **tidak pernah menahan request** (stale-while-revalidate):

- Timeframe **1D** gratis — hasilnya langsung diambil dari siklus screening utama yang sudah menghitung RSI harian untuk seluruh universe, tanpa request tambahan ke Binance.
- Timeframe lain (**15m/1H/4H/1W**) dijawab seketika dari hasil pemindaian terakhir; kalau datanya sudah basi (60 detik untuk 15m, hingga 30 menit untuk 1W), pemindaian baru berjalan **di latar belakang** dengan konkurensi terbatas — API tetap membalas instan dengan flag `isRefreshing` + progres (`progress.done/total`), dan frontend menampilkan progress bar sambil polling cepat sampai selesai. Data lama tetap ditampilkan selama pemindaian ulang.
- Setelah setiap siklus screening utama, backend **prewarm** semua timeframe non-1D di latar belakang, jadi pindah timeframe hampir selalu langsung dapat data tanpa menunggu.

## Endpoint API

| Method | Path | Keterangan |
|---|---|---|
| GET | `/api/coins/screening` | Daftar koin hasil screening + skor. Query: `minVolume24h`, `newOnly`, `minScore`, `refresh=true` |
| GET | `/api/coins/:id` | Detail pair (mis. `BTCUSDT`) + chart 7 hari + indikator |
| GET | `/api/watchlist` | Daftar watchlist |
| POST | `/api/watchlist` | Tambah koin ke watchlist `{ coinId, symbol, name, alertThreshold }` |
| DELETE | `/api/watchlist/:coinId` | Hapus dari watchlist |
| GET | `/api/signals` | Riwayat sinyal tersimpan (`limit`, `coinId`) |
| GET | `/api/rsi-screener` | Koin oversold (RSI<30) / overbought (RSI>70). Query: `interval` (`15m`\|`1h`\|`4h`\|`1d`\|`1w`, default `1d`) |
| GET | `/api/health` | Status backend & konfigurasi |
| GET | `/api/settings` | Baca pengaturan aktif (interval scan, threshold, API key opsional, dll) |
| PUT | `/api/settings` | Ubah pengaturan — tersimpan di SQLite, diterapkan langsung tanpa restart |
| POST | `/api/settings/test-notification` | Kirim pesan uji coba ke Telegram/Discord yang aktif, untuk validasi token/webhook |

## Catatan & Keterbatasan

- Universe screening terbatas pada pair yang terdaftar di **Binance USDT-M Futures** (~300+ pair) — altcoin yang tidak listing di Binance Futures tidak akan muncul.
- `id` koin di seluruh aplikasi (URL detail, watchlist, riwayat sinyal) sekarang adalah **simbol pair Binance** (mis. `BTCUSDT`), bukan lagi slug CoinGecko (mis. `bitcoin`). Watchlist/riwayat sinyal lama dari sebelum migrasi ini tidak akan cocok lagi dengan data baru.
- Deteksi "koin baru listing" memakai field `onboardDate` asli dari Binance — akurat, bukan heuristik.
- Aplikasi ini murni alat bantu screening, bukan saran finansial.
