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

  // ---------------------------------------------------------------------------
  // DATA / CANDLE
  // ---------------------------------------------------------------------------
  /// Timeframe utama untuk semua strategi.
  static const String interval = '1h';

  /// Jendela candle lokal minimal per simbol untuk komputasi indikator.
  static const int candleWindow = 500;

  /// Simbol default yang dipantau (dapat diubah lewat Pengaturan).
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

  /// Interval polling REST cadangan (mis. saat WS terputus), dalam menit.
  static const int restPollMinutes = 5;

  /// Nama unik task background workmanager.
  static const String bgTaskName = 'scalp_hourly_candle_check';
  static const String bgTaskUniqueName = 'scalp_hourly_candle_check_unique';
}
