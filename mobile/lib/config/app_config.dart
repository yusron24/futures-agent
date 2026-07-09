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
  /// Timeframe utama untuk semua strategi.
  static const String interval = '1h';

  /// Jendela candle lokal maksimal per simbol yang disimpan di cache.
  static const int candleWindow = 500;

  /// Jumlah candle yang diambil via REST saat warmup/refresh. Jauh lebih kecil
  /// dari [candleWindow] untuk menghemat bandwidth (strategi paling banyak
  /// butuh ~210 candle; sisanya diisi bertahap oleh WebSocket). Ini memangkas
  /// data yang lewat proxy hingga ~40% saat refresh.
  static const int restWarmupCandles = 300;

  /// Ambang minimal candle tertutup agar sebuah simbol dianggap "siap" dan
  /// tidak perlu di-fetch ulang saat refresh bila cache sudah mutakhir.
  static const int minReadyCandles = 260;

  /// Simbol default yang dipantau (fallback saat mode kustom / sebelum daftar
  /// top-volume berhasil diambil).
  static const List<String> defaultSymbols = <String>[
    'BTCUSDT',
    'ETHUSDT',
    'BNBUSDT',
    'SOLUSDT',
    'ADAUSDT',
    'DOGEUSDT',
    'XRPUSDT',
    'AVAXUSDT',
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
  static const String appVersion = '1.1.0';

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
