# Scalp Signals — Aplikasi Sinyal Scalping Crypto (Flutter)

Aplikasi mobile **Flutter (Dart)** yang menghasilkan sinyal scalping
probabilitas tinggi pada **timeframe 1 jam**, mengambil data pasar real-time &
historis **eksklusif dari Binance**, dan mengarahkan **seluruh lalu lintas
keluar (REST + WebSocket) melalui proxy HTTP terautentikasi**.

Menjalankan **5 strategi scalping** dengan _asymmetric risk:reward_ (minimal
1:2, idealnya 1:3+), mengagregasi sinyalnya, dan mengirim notifikasi lokal
setiap kali candle 1 jam ditutup.

> ⚠️ **Disclaimer**: Aplikasi ini untuk tujuan edukasi/riset. Sinyal bukan
> nasihat finansial. Trading kripto berisiko tinggi.

---

## ✨ Fitur

- **Dashboard**: daftar simbol dipantau + harga terakhir, perubahan 24 jam, dan
  sinyal terbaru (BUY/SELL/NEUTRAL) beserta keyakinan.
- **Detail Sinyal**: chart candlestick 1 jam dengan garis Entry / SL / TP, level
  trade, rasio R:R, ukuran posisi simulasi, dan ringkasan tiap indikator.
- **Pengaturan**: aktif/nonaktif 5 strategi, risiko per trade (% modal
  simulasi), pilihan suara & getaran notifikasi, pengelolaan simbol.
- **Riwayat Sinyal**: log yang dapat difilter, hasil (TP/SL/PENDING), dan
  statistik akurasi (win rate) — dipakai untuk membobot keyakinan.
- **Notifikasi lokal**: dipicu saat candle 1 jam ditutup & sinyal muncul
  (tanpa backend), termasuk saat aplikasi di latar belakang (`workmanager`).
- **Offline-first**: candle di-cache dengan Hive; UI menampilkan data cache saat
  tidak ada internet.
- **Tema gelap** dengan estetika crypto modern.

---

## 🏗️ Arsitektur

```
lib/
├── main.dart                     # Bootstrap: Hive, notifikasi, workmanager, AppState
├── app.dart                      # MaterialApp + navigasi bawah
├── config/
│   ├── app_config.dart           # Proxy, endpoint Binance, simbol, parameter candle
│   ├── theme.dart                # Palet & tema gelap
│   └── format.dart               # Format harga/persen/waktu
├── models/                       # Candle, Signal, StrategyResult, SymbolTicker (+ adapter Hive)
├── network/
│   ├── proxy_http_client.dart    # HttpClient sadar-proxy (REST + wss via CONNECT)
│   ├── proxy_connect_tunnel.dart # Handshake HTTP CONNECT manual -> TLS
│   ├── binance_rest_client.dart  # Klines, ticker 24h, ping (via proxy)
│   └── binance_ws_client.dart    # Combined stream kline+miniTicker (via proxy)
├── indicators/indicators.dart    # EMA, SMA, RSI, MACD, BB, ATR, Stochastic, Volume Profile, pola candle
├── strategies/                   # 5 strategi + base + registry
├── signals/signal_engine.dart    # Agregasi & pembobotan keyakinan
├── data/                         # Hive cache, repo candle/settings/riwayat + akurasi
├── services/
│   ├── notification_service.dart # flutter_local_notifications + vibration + audio
│   └── background_service.dart   # workmanager (cek candle 1 jam periodik)
├── state/app_state.dart          # Orkestrasi REST+WS, ChangeNotifier untuk UI
└── ui/                           # dashboard, detail (+chart), settings, history, widgets
```

### Aliran data
1. **Startup** → muat candle dari cache Hive (UI langsung terisi, mendukung
   offline) → fetch ulang klines + ticker via REST (proxy) → sambungkan
   WebSocket (proxy).
2. **Realtime** → stream `miniTicker` memperbarui harga; stream `kline_1h`
   memperbarui candle berjalan.
3. **Candle 1 jam ditutup** → jalankan strategi aktif → agregasi → simpan sinyal
   → notifikasi + suara/getar → evaluasi ulang sinyal pending (TP/SL) →
   perbarui akurasi.
4. **Background** → `workmanager` menjalankan langkah 3 secara periodik meski
   aplikasi tidak di depan.

---

## 🔀 Konfigurasi Proxy (WAJIB)

Semua koneksi keluar melewati proxy HTTP terautentikasi berikut:

```
http://vmsgqtlc:mms55ldv3zob@45.159.54.38:6910
```

Dikonfigurasi di `lib/config/app_config.dart`. Mekanisme:

- **REST (https) & WebSocket (wss)** → `ProxyHttpClient` menyetel
  `HttpClient.findProxy` ke proxy dan menambahkan kredensial via
  `addProxyCredentials`. Untuk target https/wss, `HttpClient` otomatis membuka
  terowongan **`HTTP CONNECT`** ke proxy, lalu menegosiasikan **TLS end-to-end
  langsung dengan Binance**.
- **WebSocket** menggunakan `WebSocket.connect(url, customClient: proxyClient)`
  sehingga handshake wss berlangsung di dalam terowongan CONNECT.
- **SSL tetap aman**: karena TLS bersifat end-to-end (proxy hanya menyalurkan
  byte terenkripsi), verifikasi sertifikat dilakukan terhadap sertifikat
  **Binance yang asli**, bukan proxy. Tidak perlu menonaktifkan verifikasi.
- **Handshake CONNECT manual** juga diimplementasikan eksplisit di
  `network/proxy_connect_tunnel.dart` (TCP → `CONNECT host:port` +
  `Proxy-Authorization: Basic` → `SecureSocket.secure`) sesuai spesifikasi.
- Jika suatu lingkungan memakai proxy yang melakukan TLS-interception dan
  memunculkan error sertifikat, aktifkan `trustProxyChain` + sediakan
  `ProxyHttpClient.proxyTrustEvaluator` (default tetap verifikasi ketat).

> Untuk mengganti proxy, ubah `proxyHost/proxyPort/proxyUser/proxyPass` di
> `app_config.dart`.

---

## 🧠 5 Strategi (timeframe 1 jam)

Setiap strategi menghasilkan **keyakinan 0–100%** dan target **asimetris**.

| # | Strategi | Ringkasan | SL | TP |
|---|----------|-----------|----|----|
| 1 | **EMA Pullback + RSI Divergence** | Pullback ke EMA50 searah tren + divergensi RSI(14) | 0,5% di luar swing atau 1,5×ATR (terlebar) | 2× jarak SL |
| 2 | **Bollinger Squeeze Breakout** | Breakout bervolume (>1,5× avg) keluar squeeze (bandwidth persentil-10) | Pita tengah (SMA20) | 2,5× jarak mid→breakout |
| 3 | **MACD Zero-Line Rejection** | Penolakan garis nol MACD + candle engulfing | Di luar candle engulfing | ≥2,5× SL / ekstensi Fib 1.618 |
| 4 | **Volume Profile S/R Flip** | Retest HVN yang berubah peran (support/resistance flip) | Level dibalik ± 0,5 ATR | HVN/POC berikutnya (≈1:3) |
| 5 | **Stochastic Pin Bar Reversal** | Pembalikan dari area ekstrem Stochastic + pin bar/engulfing | Di luar ekstrem sumbu + 0,2% | 2,5× jarak SL |

### Agregasi (`signal_engine.dart`)
- Bobot tiap sinyal = **akurasi historis strategi × keyakinan individual**.
- Beberapa strategi searah → keyakinan meningkat (probabilistic OR).
- Strategi bertentangan (bobot berimbang) → **NEUTRAL** dengan catatan.
- **SL** = terketat di antara strategi terpicu (memaksimalkan R:R);
  **TP** = target terjauh yang masuk akal.

---

## 🚀 Setup & Menjalankan

### Prasyarat
- Flutter SDK **3.27+** (Dart 3.6+). Cek: `flutter doctor`.

### Langkah
```bash
cd mobile

# 1) (Sekali) Lengkapi scaffolding platform yang tidak disertakan di repo
#    (Gradle wrapper jar, proyek Xcode, storyboard, ikon PNG). Perintah ini
#    HANYA menambahkan berkas yang belum ada — kode di lib/, pubspec, serta
#    berkas Android kustom (AndroidManifest, build.gradle, MainActivity) tetap
#    dipertahankan.
flutter create . --org com.scalpsignals --project-name scalp_signals \
  --platforms=android,ios

# 2) Ambil dependency
flutter pub get

# 3) Jalankan (perangkat/emulator terhubung)
flutter run

# Build rilis
flutter build apk --release       # Android
flutter build ios --release       # iOS (perlu macOS + Xcode)
```

> **Catatan codegen Hive**: adapter Hive (`*.g.dart`) sudah **ditulis manual**
> agar proyek langsung dibangun tanpa `build_runner`. Bila menambah field pada
> model, jalankan `dart run build_runner build --delete-conflicting-outputs`
> atau perbarui adapter secara manual.

### Menjalankan test
```bash
flutter test
```
Mencakup uji indikator (SMA/EMA/RSI/MACD/BB/ATR/Stochastic/Volume Profile) &
deteksi pola candle.

---

## 🔧 Konfigurasi cepat (`lib/config/app_config.dart`)

- `defaultSymbols` — daftar simbol default (BTC, ETH, BNB, SOL, ADA, DOGE, XRP, AVAX).
- `interval` — `1h` (timeframe strategi).
- `candleWindow` — 500 candle bergulir per simbol.
- `proxy*` — kredensial & host proxy.

---

## 📱 Izin platform
- **Android**: `INTERNET`, `POST_NOTIFICATIONS`, `VIBRATE`,
  `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK` (lihat `AndroidManifest.xml`). Core
  library desugaring diaktifkan untuk `flutter_local_notifications`.
- **iOS**: `UIBackgroundModes` (fetch/processing), izin notifikasi diminta saat
  runtime.

---

## 🎵 Aset suara
Letakkan `alert.mp3`, `chime.mp3`, `ping.mp3` di `assets/sounds/`. Bila tidak
ada, aplikasi tetap berjalan (pemutaran suara dibungkus `try/catch`).
