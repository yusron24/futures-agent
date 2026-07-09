import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../data/candle_repository.dart';
import '../data/hive_cache.dart';
import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../network/binance_rest_client.dart';
import '../services/notification_service.dart';
import '../signals/signal_engine.dart';

/// Entry point isolate background workmanager. HARUS top-level dan diberi
/// anotasi agar dapat dipanggil dari native.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await BackgroundService.runCheck();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Menjalankan pengecekan candle 1 jam secara periodik di latar belakang,
/// menghasilkan sinyal + notifikasi walau aplikasi tidak di depan.
class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      backgroundCallbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// Jadwalkan task periodik (Android). Interval minimum Android = 15 menit;
  /// kita cek tiap 15 menit dan hanya bertindak saat ada candle baru tertutup.
  static Future<void> schedulePeriodic() async {
    await Workmanager().registerPeriodicTask(
      AppConfig.bgTaskUniqueName,
      AppConfig.bgTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(AppConfig.bgTaskUniqueName);
  }

  /// Logika inti yang dijalankan di isolate background: ambil klines terbaru,
  /// deteksi candle baru tertutup, evaluasi strategi, kirim notifikasi.
  static Future<void> runCheck() async {
    await HiveCache.init();
    await NotificationService.instance.init();

    final settings = SettingsRepository();
    if (!settings.notificationsEnabled) return;

    final candles = CandleRepository();
    final history = SignalHistoryRepository();
    final engine = SignalEngine(settings, history);
    final rest = BinanceRestClient();

    try {
      for (final symbol in settings.symbols) {
        final cached = await candles.loadCached(symbol);
        final lastClosedTime = cached.isEmpty
            ? 0
            : cached.lastWhere((c) => c.isClosed,
                orElse: () => cached.last).openTime;

        // Ambil candle terbaru (cukup sedikit untuk deteksi penutupan baru).
        final fresh = await rest.fetchKlines(symbol, limit: 200);
        if (fresh.isEmpty) continue;
        await candles.replaceAll(symbol, fresh);

        final closed = candles.closedCandles(symbol);
        if (closed.isEmpty) continue;
        final newestClosed = closed.last;

        // Selesaikan sinyal pending & perbarui akurasi.
        await history.resolvePending(symbol, closed);

        // Hanya bila ada candle 1 jam BARU yang tertutup sejak terakhir.
        if (newestClosed.openTime > lastClosedTime) {
          final eval = engine.evaluate(symbol, closed);
          if (eval.signal.isActionable) {
            await history.add(eval.signal);
            await NotificationService.instance.showSignal(
              eval.signal,
              sound: settings.soundEnabled,
              vibrate: settings.vibrationEnabled,
              soundAsset: settings.soundName,
            );
          }
        }
      }
    } finally {
      rest.close();
    }
  }
}
