import 'dart:convert';

/// Konfigurasi global aplikasi: endpoint Binance, proxy wajib, daftar simbol
/// default, dan parameter data candle.
///
/// SEMUA lalu lintas keluar (REST + WebSocket) HARUS melewati [proxy].
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------------
  // PROXY (WAJIB) - semua koneksi keluar diarahkan lewat sini.
  // Format: http://user:pass@host:port
  // ---------------------------------------------------------------------------
  static const String proxyHost = '45.159.54.38';
  static const int proxyPort = 6910;
  static const String proxyUser = 'vmsgqtlc';
  static const String proxyPass = 'mms55ldv3zob';

  /// Header `Proxy-Authorization: Basic ...` yang sudah jadi (preemptive auth).
  static String get proxyAuthHeader {
    final token = base64Encode(utf8.encode('$proxyUser:$proxyPass'));
    return 'Basic $token';
  }

  /// Representasi `PROXY host:port` untuk HttpClient.findProxy.
  static String get findProxyValue => 'PROXY $proxyHost:$proxyPort';

  // ---------------------------------------------------------------------------
  // BINANCE ENDPOINTS
  // ---------------------------------------------------------------------------
  static const String restHost = 'api.binance.com';
  static const String restBaseUrl = 'https://api.binance.com';

  static const String wsHost = 'stream.binance.com';
  static const int wsPort = 9443;
  static String get wsBaseUrl => 'wss://$wsHost:$wsPort';

  /// Endpoint WS mentah (dipakai dengan pesan kontrol SUBSCRIBE untuk
  /// berlangganan banyak stream secara dinamis, cocok untuk 100+ pair).
  static String get wsRawUrl => 'wss://$wsHost:$wsPort/ws';

  // ---------------------------------------------------------------------------
  // DATA / CANDLE
  // ---------------------------------------------------------------------------
  /// Timeframe swing default untuk semua strategi. Dapat diubah pengguna ke
  /// salah satu dari [allowedIntervals] di Pengaturan.
  static const String defaultInterval = '4h';

  /// Timeframe yang boleh dipilih pengguna.
  static const List<String> allowedIntervals = <String>['1h', '4h', '1d'];

  /// Durasi satu candle (ms) untuk sebuah interval. Dipakai untuk "candle-guard"
  /// (mendeteksi batas candle baru) di refresh & background.
  static int intervalMs(String interval) {
    switch (interval) {
      case '1h':
        return 3600000;
      case '1d':
        return 86400000;
      case '4h':
      default:
        return 14400000;
    }
  }

  /// Label ramah-pengguna untuk sebuah interval.
  static String intervalLabel(String interval) {
    switch (interval) {
      case '1h':
        return '1 Jam';
      case '1d':
        return '1 Hari';
      case '4h':
      default:
        return '4 Jam';
    }
  }

  /// Jendela candle lokal maksimal per simbol yang disimpan di cache.
  static const int candleWindow = 500;

  /// Jumlah candle yang diambil via REST saat warmup/refresh. Minimal 300 per
  /// simbol agar indikator swing (mis. EMA200 + slope) valid.
  static const int restWarmupCandles = 300;

  /// Ambang minimal candle tertutup agar sebuah simbol dianggap "siap" dan
  /// tidak perlu di-fetch ulang saat refresh bila cache sudah mutakhir.
  static const int minReadyCandles = 290;

  /// Ambang keyakinan minimal (0..100) agar sebuah sinyal dianggap AKTIF.
  /// Sinyal teragregasi dengan keyakinan di bawah ini dijadikan NEUTRAL
  /// (tidak tampil, tidak notifikasi, tidak masuk riwayat).
  static const double minSignalConfidence = 70;

  // ---------------------------------------------------------------------------
  // VWAP (garis + 3 band). Dipakai chart & konfluens strategi.
  // ---------------------------------------------------------------------------
  static const bool vwapEnabledDefault = true;
  static const String vwapModeDefault = 'rolling'; // 'rolling' | 'anchored'
  static const int vwapPeriodDefault = 20;
  static const int vwapPeriodMin = 5;
  static const int vwapPeriodMax = 100;
  static const double vwapMult1 = 1.0;
  static const double vwapMult2 = 2.0;
  static const double vwapMult3 = 3.0;

  // ---------------------------------------------------------------------------
  // KEAMANAN SINYAL (Fase 1): gerbang mutu data, cooldown, circuit breaker.
  // ---------------------------------------------------------------------------
  static const bool dataQualityStrictDefault = true;
  static const bool cooldownEnabledDefault = true;
  static const int cooldownCandlesDefault = 2;
  static const int cooldownCandlesMin = 1;
  static const int cooldownCandlesMax = 10;

  /// Circuit breaker: ambang "tripped" → sistem menahan sinyal (mode aman).
  static const int cbMaxRestFailures = 3; // REST gagal beruntun
  static const int cbMaxWsDownMs = 120000; // WS putus > 2 menit
  static const int cbCandleDelayFactor = 3; // data terlambat > 3× interval

  // ---------------------------------------------------------------------------
  // KALIBRASI CONFIDENCE (Fase 2) — semua mudah di-tune.
  // ---------------------------------------------------------------------------
  /// Bobot tier strategi (core = anchor & bobot utama).
  static const double tierWeightCore = 1.0;
  static const double tierWeightSecondary = 0.6;
  static const double tierWeightExperimental = 0.25;

  /// Shrinkage sample kecil (Bayesian) — makin besar makin konservatif.
  static const double calibShrinkK = 6;

  /// Decay akurasi historis: bobot hasil lama diperkecil tiap outcome baru.
  static const double calibDecay = 0.98;

  /// Diskon korelasi antar-strategi sefamily (lembut, bukan agresif).
  static const double familyDiscount = 0.65;

  /// Kalibrasi akhir: baseline & target bukti. Bukti < target → confidence
  /// ditarik ke baseline. Target kecil agar setup bagus tetap tembus 70%.
  static const double confBaseline = 50;
  static const double evidenceTarget = 0.55;

  /// Penalti confidence.
  static const double disagreementPenalty = 30; // × bobot arah berlawanan
  static const double noCoreAnchorPenalty = 6; // arah hanya di-anchor secondary

  /// VWAP soft-veto bertingkat (Pullback EMA200) — mudah di-tune.
  static const double vwapAlignedBonus = 6; // searah VWAP
  static const double vwapBand1Penalty = 8; // sisi salah, dalam band-1 (ringan)
  static const double vwapBand2Penalty = 20; // menembus band-1 (besar)
  // band-3 (menembus band-2) → hard veto di strategi.

  // ---------------------------------------------------------------------------
  // MARKET REGIME FILTER (Fase 3) — ADX + ATR. SATU modifier confidence +
  // hard-hold khusus chop. TIDAK menentukan arah (arah tetap dari core).
  // ---------------------------------------------------------------------------
  static const bool regimeFilterEnabledDefault = true;

  /// Ambang ADX: ≥ trendMin → tren (walau ATR tinggi = boleh trading);
  /// ≤ rangeMax → range; di antara = transisi (histeresis).
  static const double regimeAdxTrendMin = 22;
  static const double regimeAdxRangeMax = 18;

  /// ATR% (atr/close) di atas ini + ADX rendah = chop tanpa arah → hard-hold.
  /// Directional volatility (ATR tinggi tapi ADX tinggi) TIDAK ditahan.
  static const double regimeAtrPctVolatile = 0.05;

  /// Penyesuaian confidence (poin). Sengaja lembut agar setup bagus tetap ≥70%.
  static const double regimeCounterTrendPenalty = 15; // lawan arah tren kuat
  static const double regimeAlignedBonus = 5; // searah tren kuat (clamp)
  static const double regimeRangeMismatchPenalty = 12; // family tren di sideways
  static const double regimeTransitionalPenalty = 3; // zona abu-abu (tunable→0)
  static const double regimeAdjMaxDown = 25; // clamp penalti maksimum
  static const double regimeAdjMaxUp = 6; // clamp bonus maksimum

  // ---------------------------------------------------------------------------
  // TRADE COST + BACKTEST + PAPER TRADING (Fase 4)
  // ---------------------------------------------------------------------------
  /// Biaya transaksi (persen per sisi) & slippage — dipakai model biaya untuk
  /// mengubah P/L teoretis (R) menjadi net. Default mendekati taker fee Binance.
  static const double tradeFeePctPerSide = 0.04; // 0,04% per sisi (masuk/keluar)
  static const double tradeSlippagePct = 0.02; // 0,02% slippage round-trip
  static const bool tradeCostEnabledDefault = true;

  /// Backtest walk-forward: candle awal yang di-skip untuk pemanasan indikator
  /// (mis. EMA200 valid) dan minimal candle agar backtest berjalan.
  static const int backtestWarmupCandles = 250;
  static const int backtestMinCandles = 300;

  // ---------------------------------------------------------------------------
  // VERSIONING SKEMA SINYAL (Fase 5) — dinaikkan saat bentuk/isi Signal berubah
  // secara semantik, untuk provenance & jalur migrasi ke depan.
  // ---------------------------------------------------------------------------
  static const int signalSchemaVersion = 2;

  /// Simbol default yang dipantau (fallback saat mode kustom / sebelum daftar
  /// top-volume berhasil diambil). Catatan: MATIC sudah di-rename menjadi POL di
  /// Binance, sehingga dipakai POLUSDT.
  static const List<String> defaultSymbols = <String>[
    'BTCUSDT',
    'ETHUSDT',
    'BNBUSDT',
    'SOLUSDT',
    'ADAUSDT',
    'POLUSDT',
    'DOTUSDT',
    'LINKUSDT',
  ];

  /// Jumlah pair top-volume yang dipantau saat mode "Top Volume".
  static const int topPairsCount = 100;

  /// Aset quote yang dipertimbangkan untuk peringkat volume.
  static const String quoteAsset = 'USDT';

  /// Konkurensi default saat mengambil klines banyak simbol via REST.
  /// Nilai tinggi = refresh lebih cepat (memakai lebih banyak koneksi/bandwidth
  /// paralel lewat proxy). Dapat diubah pengguna di Pengaturan.
  static const int defaultFetchConcurrency = 20;
  static const int minFetchConcurrency = 4;
  static const int maxFetchConcurrency = 40;

  /// Interval polling ticker 24 jam via REST saat mode hemat bandwidth
  /// (stream miniTicker dimatikan), dalam detik.
  static const int tickerPollSeconds = 90;

  /// Interval polling REST cadangan (mis. saat WS terputus), dalam menit.
  static const int restPollMinutes = 5;

  /// Nama unik task background workmanager.
  static const String bgTaskName = 'scalp_hourly_candle_check';
  static const String bgTaskUniqueName = 'scalp_hourly_candle_check_unique';

  // ---------------------------------------------------------------------------
  // PEMBARUAN APLIKASI (GitHub Releases)
  // ---------------------------------------------------------------------------
  /// Versi aplikasi saat ini (samakan dengan `version` di pubspec.yaml).
  static const String appVersion = '2.0.0';

  static const String repoOwner = 'yusron24';
  static const String repoName = 'futures-agent';

  /// Tag rilis yang selalu menunjuk build terbaru.
  static const String releaseTag = 'apk-latest';

  /// Tautan langsung ke APK terbaru (satu klik untuk mengunduh & memasang).
  static String get latestApkUrl =>
      'https://github.com/$repoOwner/$repoName/releases/download/$releaseTag/app-release.apk';

  /// Halaman rilis (alternatif bila unduhan langsung diblokir).
  static String get releasePageUrl =>
      'https://github.com/$repoOwner/$repoName/releases/tag/$releaseTag';

  /// Endpoint API publik GitHub untuk info rilis terbaru (cek waktu update).
  static String get releaseApiUrl =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$releaseTag';
}
