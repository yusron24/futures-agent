import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:scalp_signals/data/settings_repository.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/signals/backtest_engine.dart';
import 'package:scalp_signals/signals/signal_engine.dart';

/// Candle datar (tanpa tren/pola) dengan spacing 4h agar lolos gerbang mutu data
/// namun tak memicu strategi apa pun.
List<Candle> _flat(int n) {
  const step = 14400000; // 4h
  final out = <Candle>[];
  for (int i = 0; i < n; i++) {
    out.add(Candle(
      openTime: i * step,
      open: 100,
      high: 100.3,
      low: 99.7,
      close: 100,
      volume: 100,
      closeTime: i * step + 1,
    ));
  }
  return out;
}

void main() {
  group('EvalReason 1:1 dengan cabang engine (Fase 5)', () {
    late SignalEngine engine;

    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('hive_reason');
      Hive.init(dir.path);
      await Hive.openBox('settings');
    });

    setUp(() {
      engine = SignalEngine(SettingsRepository(), InMemoryStats());
    });

    test('candle kurang dari minimal gerbang data → dataBlocked', () {
      final eval = engine.evaluate('BTCUSDT', _flat(40));
      expect(eval.reason, EvalReason.dataBlocked);
      expect(eval.signal.isActionable, false);
    });

    test('data cukup tapi tak ada setup → noSetup', () {
      final candles = _flat(120);
      final eval = engine.evaluate('BTCUSDT', candles,
          nowMsOverride: candles.last.closeTime);
      expect(eval.reason, EvalReason.noSetup);
      expect(eval.signal.isActionable, false);
    });
  });
}
