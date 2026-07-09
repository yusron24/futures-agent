import 'package:hive_flutter/hive_flutter.dart';

import '../models/candle.dart';
import '../models/signal.dart';

/// Inisialisasi Hive dan pembukaan seluruh box cache aplikasi.
class HiveCache {
  HiveCache._();

  static const String candleBoxPrefix = 'candles_';
  static const String signalBox = 'signals';
  static const String settingsBox = 'settings';
  static const String accuracyBox = 'strategy_accuracy';

  static bool _initialized = false;

  /// Panggil sekali saat startup (juga dari isolate background workmanager).
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(CandleAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SignalAdapter());

    await Hive.openBox(settingsBox);
    await Hive.openBox<Signal>(signalBox);
    await Hive.openBox(accuracyBox);
    _initialized = true;
  }

  /// Box candle per simbol (lazy dibuka saat dibutuhkan).
  static Future<Box<Candle>> candleBox(String symbol) async {
    final name = '$candleBoxPrefix${symbol.toLowerCase()}';
    if (Hive.isBoxOpen(name)) return Hive.box<Candle>(name);
    return Hive.openBox<Candle>(name);
  }

  static Box settings() => Hive.box(settingsBox);
  static Box<Signal> signals() => Hive.box<Signal>(signalBox);
  static Box accuracy() => Hive.box(accuracyBox);
}
