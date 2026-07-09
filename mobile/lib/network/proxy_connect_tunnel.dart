import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/app_config.dart';

/// Membuka terowongan `HTTP CONNECT` manual ke proxy lalu meng-upgrade soket
/// mentah menjadi TLS ([SecureSocket]) langsung ke host tujuan.
///
/// Ini adalah implementasi eksplisit dari mekanisme yang diminta: soket kustom
/// yang melakukan handshake `HTTP CONNECT` ke proxy sebelum lapisan di atasnya
/// (TLS lalu WebSocket) dijalankan.
///
/// Alur:
///   1. TCP connect ke proxy.
///   2. Kirim `CONNECT host:port` + `Proxy-Authorization: Basic ...`.
///   3. Verifikasi balasan `200 Connection Established`.
///   4. `SecureSocket.secure` di atas soket yang sama -> TLS end-to-end ke host.
///
/// Catatan penting: verifikasi TLS dilakukan terhadap sertifikat host tujuan
/// (Binance), bukan proxy, sehingga keamanan SSL tetap terjaga. Setelah balasan
/// CONNECT, klien-lah yang berbicara lebih dulu (TLS ClientHello), jadi tidak
/// ada byte sisa milik lapisan atas yang hilang.
class ProxyConnectTunnel {
  /// Buka terowongan ke [targetHost]:[targetPort] melalui proxy aplikasi dan
  /// kembalikan [SecureSocket] yang siap dipakai.
  static Future<SecureSocket> open({
    required String targetHost,
    required int targetPort,
    Duration timeout = const Duration(seconds: 20),
    bool Function(X509Certificate cert)? onBadCertificate,
  }) async {
    final socket = await Socket.connect(
      AppConfig.proxyHost,
      AppConfig.proxyPort,
      timeout: timeout,
    );
    socket.setOption(SocketOption.tcpNoDelay, true);

    // Susun permintaan CONNECT dengan Basic auth preemptive.
    final request = StringBuffer()
      ..write('CONNECT $targetHost:$targetPort HTTP/1.1\r\n')
      ..write('Host: $targetHost:$targetPort\r\n')
      ..write('Proxy-Authorization: ${AppConfig.proxyAuthHeader}\r\n')
      ..write('Proxy-Connection: Keep-Alive\r\n')
      ..write('User-Agent: scalp-signals/1.0\r\n')
      ..write('\r\n');

    // Baca balasan CONNECT tanpa membatalkan subscription (agar soket tidak
    // ikut tertutup). Subscription yang di-pause diserahkan ke SecureSocket.
    final headerCompleter = Completer<void>();
    final buffer = BytesBuilder(copy: false);
    late StreamSubscription<Uint8List> sub;

    sub = socket.listen(
      (chunk) {
        if (headerCompleter.isCompleted) return;
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        final end = _indexOfHeaderEnd(bytes);
        if (end == -1) return;

        final statusLine = ascii.decode(bytes.sublist(0, end)).split('\r\n').first;
        sub.pause();
        final code = _parseStatusCode(statusLine);
        if (code == 200) {
          headerCompleter.complete();
        } else {
          headerCompleter.completeError(
            HttpException('Proxy CONNECT gagal: $statusLine'),
          );
        }
      },
      onError: (Object e, StackTrace st) {
        if (!headerCompleter.isCompleted) headerCompleter.completeError(e, st);
      },
      onDone: () {
        if (!headerCompleter.isCompleted) {
          headerCompleter.completeError(
            const HttpException('Proxy menutup koneksi sebelum CONNECT selesai'),
          );
        }
      },
      cancelOnError: false,
    );

    socket.add(utf8.encode(request.toString()));
    await socket.flush();

    try {
      await headerCompleter.future.timeout(timeout);
    } catch (e) {
      await sub.cancel();
      socket.destroy();
      rethrow;
    }

    // Upgrade ke TLS. SecureSocket.secure mengambil alih soket beserta
    // subscription yang sedang di-pause lalu melanjutkannya.
    final secure = await SecureSocket.secure(
      socket,
      host: targetHost,
      onBadCertificate: onBadCertificate,
    );
    secure.setOption(SocketOption.tcpNoDelay, true);
    return secure;
  }

  /// Index tepat setelah akhir header HTTP (`\r\n\r\n`), atau -1.
  static int _indexOfHeaderEnd(Uint8List b) {
    for (int i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int _parseStatusCode(String statusLine) {
    // Contoh: "HTTP/1.1 200 Connection Established"
    final parts = statusLine.split(' ');
    if (parts.length >= 2) {
      return int.tryParse(parts[1]) ?? -1;
    }
    return -1;
  }
}
