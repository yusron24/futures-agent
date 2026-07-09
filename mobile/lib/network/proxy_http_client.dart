import 'dart:io';

import '../config/app_config.dart';

/// Membuat [HttpClient] yang seluruh lalu lintasnya (REST maupun handshake
/// WebSocket wss) diarahkan melalui proxy HTTP terautentikasi milik aplikasi.
///
/// Untuk target **https** dan **wss**, HttpClient secara otomatis membuka
/// terowongan `HTTP CONNECT` ke proxy lalu menegosiasikan TLS end-to-end
/// langsung dengan Binance. Artinya:
///   * Verifikasi sertifikat tetap dilakukan terhadap sertifikat Binance yang
///     asli (bukan sertifikat proxy) — SSL tetap aman.
///   * Autentikasi proxy dikirim lewat header `Proxy-Authorization`.
///
/// Karena TLS bersifat end-to-end (proxy hanya menyalurkan byte terenkripsi),
/// tidak diperlukan trust khusus terhadap sertifikat proxy pada kondisi normal.
/// Bila di lingkungan tertentu proxy melakukan TLS-interception dan
/// menyebabkan error sertifikat, aktifkan [trustProxyChain] agar validasi
/// diarahkan ke [ProxyHttpClient.proxyTrustEvaluator] (secara default tetap
/// menolak sertifikat tidak dikenal supaya aman).
class ProxyHttpClient {
  ProxyHttpClient._();

  /// Callback opsional untuk mengevaluasi rantai sertifikat bila proxy
  /// melakukan interception. Kembalikan `true` HANYA jika rantai proxy sudah
  /// diverifikasi valid oleh aplikasi. Default: null (verifikasi ketat).
  static bool Function(X509Certificate cert, String host, int port)?
      proxyTrustEvaluator;

  /// Bangun HttpClient sadar-proxy.
  static HttpClient create({
    Duration connectionTimeout = const Duration(seconds: 20),
    bool trustProxyChain = false,
  }) {
    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..idleTimeout = const Duration(seconds: 30)
      // Arahkan SEMUA URI melalui proxy. HttpClient akan otomatis memakai
      // CONNECT untuk skema https/wss.
      ..findProxy = (uri) => AppConfig.findProxyValue;

    // Kredensial proxy (Basic). Dipakai HttpClient saat proxy membalas 407
    // pada permintaan CONNECT/GET.
    client.addProxyCredentials(
      AppConfig.proxyHost,
      AppConfig.proxyPort,
      '', // realm kosong -> cocokkan tantangan Basic apa pun dari proxy
      HttpClientBasicCredentials(AppConfig.proxyUser, AppConfig.proxyPass),
    );

    // Verifikasi sertifikat. Default ketat; hanya longgar bila diminta dan ada
    // evaluator eksplisit yang memvalidasi rantai proxy.
    client.badCertificateCallback = (cert, host, port) {
      if (trustProxyChain && proxyTrustEvaluator != null) {
        return proxyTrustEvaluator!(cert, host, port);
      }
      return false; // tolak sertifikat yang tidak lolos verifikasi standar
    };

    return client;
  }
}
