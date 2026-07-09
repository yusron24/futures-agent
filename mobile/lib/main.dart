import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/candle_repository.dart';
import 'data/hive_cache.dart';
import 'data/settings_repository.dart';
import 'data/signal_history_repository.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cache lokal (Hive) + notifikasi.
  await HiveCache.init();
  await NotificationService.instance.init();

  // Eksekusi latar belakang untuk cek candle 1 jam (Android).
  try {
    await BackgroundService.initialize();
    await BackgroundService.schedulePeriodic();
  } catch (_) {
    // Beberapa platform (mis. iOS simulator) tidak mendukung workmanager;
    // aplikasi tetap berjalan penuh saat di depan.
  }

  final settings = SettingsRepository();
  final candles = CandleRepository();
  final history = SignalHistoryRepository();

  final appState = AppState(
    settings: settings,
    candles: candles,
    history: history,
  );
  // Mulai orkestrasi (muat cache -> REST -> WebSocket via proxy).
  appState.init();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const ScalpSignalsApp(),
    ),
  );
}
