# Altcoin Screener

Aplikasi full-stack untuk mendeteksi dan menyaring altcoin dengan potensi pergerakan harga besar, menggunakan data publik CoinGecko. Backend Express + SQLite + Socket.IO, frontend React (Vite) + Tailwind CSS dengan tema gelap ala terminal trading.

## Struktur Proyek

```
backend/    Express API, scoring engine, scheduler (cron), SQLite (watchlist + riwayat sinyal)
frontend/   React (Vite) + Tailwind + Recharts, dashboard screening real-time
```

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

| Variable | Keterangan |
|---|---|
| `PORT` | Port backend (default 5000) |
| `COINGECKO_API_URL` | Base URL CoinGecko (default tier gratis) |
| `COINGECKO_API_KEY` | Opsional, untuk CoinGecko Pro/Demo API key |
| `LUNARCRUSH_API_KEY` / `SANTIMENT_API_KEY` / `SOCIAL_API_KEY` | Opsional, mengaktifkan skor momentum sosial. Tanpa key, skor sosial memakai nilai netral placeholder (tetap dihitung dalam skor total, tidak mempengaruhi ranking secara bias) |
| `DETAILED_COINS_LIMIT` | Jumlah koin top-mover yang dihitung indikator detail (RSI/MACD/volume spike) per siklus, default 60. Dibatasi agar tidak melebihi rate limit gratis CoinGecko (~10-30 request/menit) |
| `SCAN_INTERVAL_MINUTES` | Interval scheduler penghitungan ulang skor (default 5 menit) |
| `SIGNAL_SCORE_THRESHOLD` | Skor minimum agar sebuah koin dicatat sebagai "sinyal" ke riwayat (default 75) |
| `CORS_ORIGIN` | Origin frontend yang diizinkan (default `http://localhost:5173`) |

## Cara Kerja Screening

1. Setiap `SCAN_INTERVAL_MINUTES` menit, backend mengambil 250 koin teratas dari `/coins/markets` CoinGecko (stablecoin & wrapped token difilter otomatis).
2. Untuk semua koin dihitung metrik "murah" (tanpa request tambahan): perubahan harga 1h/24h/7d, volatilitas (high-low 24h vs harga rata-rata), dan heuristik "baru listing" (berdasarkan `atl_date`).
3. ~60 koin dengan pergerakan paling signifikan (plus semua koin di watchlist) mendapat analisis mendalam: RSI(14) & MACD(12,26,9) dihitung dari histori harga 30 hari, serta rasio volume spike (volume hari ini vs rata-rata harian sebelumnya) — dilakukan sekuensial dengan jeda antar-request untuk menghindari rate limit CoinGecko (auto-retry dengan exponential backoff saat kena HTTP 429).
4. Skor potensi 0-100 dihitung dari kombinasi berbobot: Volume Spike 30%, Momentum Harga 25%, Volatilitas 15%, RSI 15%, Sosial 15% (placeholder netral jika API sosial tidak dikonfigurasi).
5. Koin dengan skor ≥ threshold dicatat ke tabel `signals` di SQLite dan di-broadcast lewat WebSocket (`screening:update`, `signals:new`, `watchlist:alert`) agar dashboard & notifikasi browser update real-time.
6. Frontend melakukan polling setiap 30 detik (bisa dimatikan) dan juga mendengarkan event WebSocket untuk refresh instan.

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

## Catatan & Keterbatasan

- CoinGecko free tier membatasi rate limit; itulah kenapa indikator detail (RSI/MACD/volume spike) hanya dihitung untuk subset top-mover per siklus, bukan seluruh 250 koin sekaligus. Koin lain tetap tampil dengan skor berbasis metrik murah dan placeholder netral untuk metrik yang belum dihitung (ditandai `~` di tabel dashboard).
- Deteksi "koin baru listing" adalah heuristik berbasis tanggal all-time-low, karena CoinGecko tidak menyediakan tanggal listing langsung di endpoint publik.
- Aplikasi ini murni alat bantu screening, bukan saran finansial.
