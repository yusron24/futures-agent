import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../data/candle_repository.dart';
import '../data/hive_cache.dart';
import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../indicators/vwap.dart';
import '../network/binance_rest_client.dart';
import '../services/notification_service.dart';
import '../services/system_health.dart';
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

    // Samakan konfigurasi VWAP di isolate background agar sinyal konsisten.
    VwapConfig.mode = VwapConfig.modeFromString(settings.vwapMode);
    VwapConfig.period = settings.vwapPeriod;
    VwapConfig.enabledForSignals = settings.vwapEnabled;

    // Candle-guard: keluar cepat bila step candle timeframe ini sudah diproses.
    final stepMs = AppConfig.intervalMs(settings.interval);
    final currentStepStart =
        (DateTime.now().millisecondsSinceEpoch ~/ stepMs) * stepMs;
    if (settings.bgLastProcessedHour >= currentStepStart) return;

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
        final probe =
            await rest.fetchKlines(symbol, limit: 2, interval: settings.interval);
        if (probe.isEmpty) continue;
        final probeNewestClosed =
            probe.lastWhere((c) => c.isClosed, orElse: () => probe.first);
        if (probeNewestClosed.openTime <= lastClosedTime) {
          processedAny = true; // sudah mutakhir untuk step ini
          continue;
        }

        // Ada candle baru -> baru sekarang unduh jendela penuh (sekali/step).
        final fresh = await rest.fetchKlines(symbol,
            limit: AppConfig.restWarmupCandles, interval: settings.interval);
        if (fresh.isEmpty) continue;
        await candles.replaceAll(symbol, fresh);
        processedAny = true;

        final closed = candles.closedCandles(symbol);
        if (closed.isEmpty) continue;
        SystemHealth.instance.recordData();

        // Selesaikan sinyal pending + pasang cooldown setelah TP/SL.
        final cooldownMs = settings.cooldownEnabled
            ? settings.cooldownCandles * AppConfig.intervalMs(settings.interval)
            : 0;
        await history.resolvePending(symbol, closed, cooldownMs: cooldownMs);

        // Engine sudah menerapkan gerbang mutu data, cooldown, & filter 70%.
        final eval = engine.evaluate(symbol, closed);
        final held = SystemHealth.instance
            .signalsHeld(intervalMs: AppConfig.intervalMs(settings.interval));
        if (eval.signal.isActionable && !held) {
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
        settings.bgLastProcessedHour = currentStepStart;
      }
    } finally {
      rest.close();
    }
  }
}
