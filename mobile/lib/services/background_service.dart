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

  /// Logika inti yang dijalankan di isolate background: deteksi candle 1 jam
  /// baru tertutup, evaluasi strategi, kirim notifikasi.
  ///
  /// Dipanggil oleh workmanager (tiap ~15 mnt) DAN foreground service (tiap
  /// ~60 dtk), sehingga harus sangat hemat:
  ///  1. Hour-guard: candle 1h hanya tertutup sekali per jam — bila jam
  ///     berjalan sudah pernah diproses, langsung keluar tanpa jaringan.
  ///  2. Probe murah dulu (2 candle) per simbol; unduhan penuh hanya saat
  ///     benar-benar ada candle baru tertutup (sekali per jam per simbol).
  static Future<void> runCheck() async {
    await HiveCache.init();
    await NotificationService.instance.init();

    final settings = SettingsRepository();
    if (!settings.notificationsEnabled) return;

    // Hour-guard: keluar cepat bila jam ini sudah diproses.
    const hourMs = 3600000;
    final currentHourStart =
        (DateTime.now().millisecondsSinceEpoch ~/ hourMs) * hourMs;
    if (settings.bgLastProcessedHour >= currentHourStart) return;

    final candles = CandleRepository();
    final history = SignalHistoryRepository();
    final engine = SignalEngine(settings, history);
    final rest = BinanceRestClient();

    var processedAny = false;
    try {
      // Batasi jumlah simbol di isolate background agar hemat baterai/data
      // (mode top-volume bisa 100+ pair). Simbol teratas (volume tertinggi)
      // diprioritaskan. Jumlah dapat diatur di Pengaturan.
      final bgMaxSymbols = settings.backgroundSymbolCap;
      final all = settings.symbols;
      final subset =
          all.length > bgMaxSymbols ? all.sublist(0, bgMaxSymbols) : all;
      for (final symbol in subset) {
        final cached = await candles.loadCached(symbol);
        final lastClosedTime = cached.isEmpty
            ? 0
            : cached.lastWhere((c) => c.isClosed,
                orElse: () => cached.last).openTime;

        // Probe murah: 2 candle terakhir cukup untuk tahu apakah ada candle
        // baru yang tertutup sejak pengecekan sebelumnya.
        final probe = await rest.fetchKlines(symbol, limit: 2);
        if (probe.isEmpty) continue;
        final probeNewestClosed =
            probe.lastWhere((c) => c.isClosed, orElse: () => probe.first);
        if (probeNewestClosed.openTime <= lastClosedTime) {
          processedAny = true; // sudah mutakhir untuk jam ini
          continue;
        }

        // Ada candle baru -> baru sekarang unduh jendela penuh (sekali/jam).
        final fresh = await rest.fetchKlines(symbol, limit: 300);
        if (fresh.isEmpty) continue;
        await candles.replaceAll(symbol, fresh);
        processedAny = true;

        final closed = candles.closedCandles(symbol);
        if (closed.isEmpty) continue;

        // Selesaikan sinyal pending & perbarui akurasi.
        await history.resolvePending(symbol, closed);

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
      if (processedAny) {
        settings.bgLastProcessedHour = currentHourStart;
      }
    } finally {
      rest.close();
    }
  }
}
