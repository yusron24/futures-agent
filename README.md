# Altcoin Screener

Aplikasi full-stack untuk mendeteksi dan menyaring altcoin dengan potensi pergerakan harga besar, menggunakan data publik CoinGecko. Backend Express + SQLite + Socket.IO, frontend React (Vite) + Tailwind CSS dengan tema gelap ala terminal trading.

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
cp .env.example .env   # sesuaikan API key jika ada, defaultnya sudah bisa langsung jalan
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

## Konfigurasi (.env backend)

`.env` hanya dipakai sebagai **nilai default awal**. Setelah backend jalan, buka halaman **Pengaturan** di `http://localhost:5173/settings` untuk mengubah API key, interval scan, threshold sinyal, dan jumlah koin detail per siklus langsung dari browser — tersimpan di SQLite dan diterapkan seketika tanpa perlu edit `.env` atau restart backend.

| Variable | Keterangan |
|---|---|
| `PORT` | Port backend (default 5000) |
| `COINGECKO_API_URL` | Base URL CoinGecko (default tier gratis) |
| `COINGECKO_API_KEY` | Opsional, untuk CoinGecko Pro/Demo API key — bisa juga diisi lewat halaman Pengaturan |
| `LUNARCRUSH_API_KEY` / `SOCIAL_API_KEY` | Opsional, mengaktifkan skor momentum sosial. Tanpa key, skor sosial memakai nilai netral placeholder (tetap dihitung dalam skor total, tidak mempengaruhi ranking secara bias) — bisa juga diisi lewat halaman Pengaturan |
| `CRYPTOQUANT_API_KEY` | Opsional, exchange inflow/outflow & supply-on-exchange (BTC/ETH; dipakai sebagai proxy makro untuk altcoin lain) — bisa juga diisi lewat halaman Pengaturan |
| `WHALE_ALERT_API_KEY` | Opsional, jumlah transaksi whale >$100k (1 jam terakhir) per koin dari [Whale Alert](https://whale-alert.io) — bisa juga diisi lewat halaman Pengaturan |
| `GLASSNODE_API_KEY` | Dicadangkan untuk pengembangan berikutnya (belum tersambung ke endpoint live) |
| `DETAILED_COINS_LIMIT` | Jumlah koin top-mover yang dihitung indikator detail (RSI/MACD/volume spike/on-chain) per siklus, default 60. Dibatasi agar tidak melebihi rate limit gratis CoinGecko (~10-30 request/menit) — bisa diubah lewat halaman Pengaturan |
| `SCAN_INTERVAL_MINUTES` | Interval scheduler penghitungan ulang skor (default 5 menit) — bisa diubah lewat halaman Pengaturan |
| `SIGNAL_SCORE_THRESHOLD` | Skor minimum agar sebuah koin dicatat sebagai "sinyal" ke riwayat (default 75) — bisa diubah lewat halaman Pengaturan |
| `CORS_ORIGIN` | Origin frontend yang diizinkan (default `http://localhost:5173`) |
| `FRONTEND_URL` | URL publik frontend, dipakai untuk link "lihat detail" di notifikasi Telegram/Discord (default `http://localhost:5173`) |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` / `TELEGRAM_ENABLED` | Opsional, notifikasi Telegram — bisa juga diisi & di-toggle lewat halaman Pengaturan |
| `DISCORD_WEBHOOK_URL` / `DISCORD_ENABLED` | Opsional, notifikasi Discord — bisa juga diisi & di-toggle lewat halaman Pengaturan |

## Cara Kerja Screening

1. Setiap `SCAN_INTERVAL_MINUTES` menit, backend mengambil 250 koin teratas dari `/coins/markets` CoinGecko (stablecoin & wrapped token difilter otomatis).
2. Untuk semua koin dihitung metrik "murah" (tanpa request tambahan): perubahan harga 1h/24h/7d, volatilitas (high-low 24h vs harga rata-rata), dan heuristik "baru listing" (berdasarkan `atl_date`).
3. ~60 koin dengan pergerakan paling signifikan (plus semua koin di watchlist) mendapat analisis mendalam: RSI(14) & MACD(12,26,9) dihitung dari histori harga 30 hari, rasio volume spike (volume hari ini vs rata-rata harian sebelumnya), dan metrik on-chain (lihat bawah) — dilakukan sekuensial dengan jeda antar-request untuk menghindari rate limit CoinGecko (auto-retry dengan exponential backoff saat kena HTTP 429).
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

Setiap koin hanya mengirim satu notifikasi per siklus meski memenuhi keduanya. Pesan berisi nama, simbol, skor, perubahan harga 24h, volume spike, RSI, dan link ke halaman detail (`FRONTEND_URL`). Aktifkan dan isi kredensialnya lewat halaman **Pengaturan** (tersimpan di SQLite, langsung berlaku tanpa restart), lalu pakai tombol **Kirim Notifikasi Uji Coba** untuk memastikan token/webhook-nya valid — hasil per-channel (berhasil/gagal beserta alasannya) langsung ditampilkan.

**Cara mendapatkan Telegram Bot Token & Chat ID:**
1. Chat [@BotFather](https://t.me/BotFather) di Telegram, kirim `/newbot`, ikuti instruksinya → dapat **Bot Token** (format `123456789:AA...`).
2. Mulai chat dengan bot Anda (klik link yang diberikan BotFather) dan kirim pesan apa saja, atau tambahkan bot ke grup yang diinginkan.
3. Buka `https://api.telegram.org/bot<TOKEN>/getUpdates` di browser (ganti `<TOKEN>`), cari field `"chat":{"id": ...}` di hasil JSON-nya → itu **Chat ID** Anda (untuk grup, angkanya negatif).

**Cara mendapatkan Discord Webhook URL:**
1. Di server Discord Anda, buka **Server Settings → Integrations → Webhooks → New Webhook**.
2. Pilih channel tujuan, beri nama (opsional), lalu klik **Copy Webhook URL**.
3. Tempel URL tersebut di halaman Pengaturan.

Jika token/webhook salah atau ada masalah jaringan, error-nya di-catch dan dicatat di log backend (`[notification] Telegram/Discord send failed: ...`) tanpa menghentikan siklus screening atau mempengaruhi koin lain.

## Endpoint API

| Method | Path | Keterangan |
|---|---|---|
| GET | `/api/coins/screening` | Daftar koin hasil screening + skor. Query: `minMarketCap`, `newOnly`, `category`, `minScore`, `refresh=true` |
| GET | `/api/coins/:id` | Detail koin + chart 7 hari + indikator |
| GET | `/api/watchlist` | Daftar watchlist |
| POST | `/api/watchlist` | Tambah koin ke watchlist `{ coinId, symbol, name, alertThreshold }` |
| DELETE | `/api/watchlist/:coinId` | Hapus dari watchlist |
| GET | `/api/signals` | Riwayat sinyal tersimpan (`limit`, `coinId`) |
| GET | `/api/categories` | Daftar kategori/sektor koin |
| GET | `/api/health` | Status backend & konfigurasi |
| GET | `/api/settings` | Baca pengaturan aktif (API key, interval scan, threshold, dll) |
| PUT | `/api/settings` | Ubah pengaturan — tersimpan di SQLite, diterapkan langsung tanpa restart |
| POST | `/api/settings/test-notification` | Kirim pesan uji coba ke Telegram/Discord yang aktif, untuk validasi token/webhook |

## Catatan & Keterbatasan

- CoinGecko free tier membatasi rate limit; itulah kenapa indikator detail (RSI/MACD/volume spike) hanya dihitung untuk subset top-mover per siklus, bukan seluruh 250 koin sekaligus. Koin lain tetap tampil dengan skor berbasis metrik murah dan placeholder netral untuk metrik yang belum dihitung (ditandai `~` di tabel dashboard).
- Deteksi "koin baru listing" adalah heuristik berbasis tanggal all-time-low, karena CoinGecko tidak menyediakan tanggal listing langsung di endpoint publik.
- Aplikasi ini murni alat bantu screening, bukan saran finansial.
