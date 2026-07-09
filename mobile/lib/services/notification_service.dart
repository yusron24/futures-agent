import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/signal.dart';

/// Menangani notifikasi lokal, suara, dan getaran saat sinyal baru dihasilkan.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audio = AudioPlayer();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Minta izin (Android 13+ / iOS).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _ready = true;
  }

  static final AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'scalp_signals',
    'Sinyal Scalping',
    channelDescription: 'Notifikasi saat candle 1 jam ditutup & sinyal muncul',
    importance: Importance.high,
    priority: Priority.high,
  );

  NotificationDetails get _details => NotificationDetails(
        android: _androidDetails,
        iOS: const DarwinNotificationDetails(),
      );

  /// Tampilkan notifikasi sinyal + efek suara/getar sesuai preferensi.
  Future<void> showSignal(
    Signal signal, {
    bool sound = true,
    bool vibrate = true,
    String soundAsset = 'alert.mp3',
  }) async {
    if (!_ready) await init();
    if (!signal.isActionable) return;

    final title = '${signal.direction} ${signal.symbol} '
        '(${signal.confidence.toStringAsFixed(0)}%)';
    final body =
        'Entry ${signal.entry.toStringAsFixed(4)} · SL ${signal.stopLoss.toStringAsFixed(4)} '
        '· TP ${signal.takeProfit.toStringAsFixed(4)} · R:R 1:${signal.riskReward.toStringAsFixed(1)}';

    await _plugin.show(
      signal.key.hashCode,
      title,
      body,
      _details,
      payload: signal.symbol,
    );

    if (vibrate) {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (hasVibrator) {
        Vibration.vibrate(pattern: const [0, 200, 100, 200]);
      }
    }
    if (sound) {
      try {
        await _audio.play(AssetSource('sounds/$soundAsset'));
      } catch (_) {
        // Aset suara opsional; abaikan bila tidak ada.
      }
    }
  }

  /// Notifikasi ringkas dari isolate background (tanpa suara kustom).
  Future<void> showSimple(String title, String body) async {
    if (!_ready) await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      _details,
    );
  }
}
