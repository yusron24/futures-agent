import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background_service.dart';

/// Entry point isolate foreground service. HARUS top-level + anotasi agar dapat
/// dipanggil dari native.
@pragma('vm:entry-point')
void foregroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(SignalTaskHandler());
}

/// Handler yang berjalan di isolate foreground service. Memakai ulang
/// [BackgroundService.runCheck] (deteksi candle 1 jam baru + kirim notifikasi
/// sinyal) pada saat mulai dan setiap interval berulang.
class SignalTaskHandler extends TaskHandler {
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  /// Cegah tumpang tindih bila satu siklus belum selesai.
  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await BackgroundService.runCheck();
    } catch (_) {
      // Abaikan; coba lagi siklus berikutnya.
    } finally {
      _busy = false;
    }
  }
}

/// Pembungkus konfigurasi & kontrol foreground service Android.
///
/// Fitur ini hanya relevan di Android; di platform lain seluruh metode menjadi
/// no-op sehingga aman dipanggil dari kode lintas-platform.
class ForegroundService {
  ForegroundService._();

  static const int _serviceId = 2718;
  static const String _channelId = 'scalp_foreground';

  /// Interval pengecekan sinyal di latar belakang (ms). 60 dtk jauh lebih rapat
  /// daripada workmanager (15 mnt) tapi tetap hemat karena hanya cek candle.
  static const int _repeatIntervalMs = 60 * 1000;

  static bool get _supported => Platform.isAndroid;

  /// Panggil sekali saat startup (setelah WidgetsFlutterBinding).
  static void init() {
    if (!_supported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Pemantauan Sinyal',
        channelDescription:
            'Menjaga aplikasi memantau sinyal saat berjalan di latar belakang.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_repeatIntervalMs),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  /// Mulai foreground service (idempoten). [symbolCount] hanya untuk teks
  /// notifikasi.
  static Future<void> start({int symbolCount = 0}) async {
    if (!_supported) return;
    // Pastikan izin notifikasi (Android 13+).
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) return;

    final text = symbolCount > 0
        ? 'Memantau $symbolCount pair — sinyal tetap aktif walau app ditutup'
        : 'Sinyal tetap aktif walau aplikasi ditutup';
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Scalp Signals',
      notificationText: text,
      callback: foregroundStartCallback,
    );
  }

  /// Hentikan foreground service (idempoten).
  static Future<void> stop() async {
    if (!_supported) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
