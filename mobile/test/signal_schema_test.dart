import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:scalp_signals/config/app_config.dart';
import 'package:scalp_signals/models/signal.dart';

Signal _sig() => Signal(
      symbol: 'BTCUSDT',
      direction: 'BUY',
      entry: 100,
      stopLoss: 98,
      takeProfit: 105,
      confidence: 80,
      riskReward: 2.5,
      triggeredStrategies: const ['a', 'b'],
      timestamp: 1000,
      outcome: SignalOutcome.pending,
    );

void main() {
  group('Signal schemaVersion (Fase 5)', () {
    test('sinyal baru bertanda versi skema saat ini', () {
      expect(_sig().schemaVersion, AppConfig.signalSchemaVersion);
    });

    test('copyWith mempertahankan schemaVersion', () {
      final s = _sig().copyWith(outcome: SignalOutcome.tpHit, profitLoss: 2.5);
      expect(s.schemaVersion, AppConfig.signalSchemaVersion);
      expect(s.outcome, SignalOutcome.tpHit);
    });

    test('round-trip adapter Hive mempertahankan semua field', () async {
      final dir = Directory.systemTemp.createTempSync('hive_schema');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SignalAdapter());
      final box = await Hive.openBox<Signal>('signals_schema_test');
      final s = _sig().copyWith(outcome: SignalOutcome.slHit, profitLoss: -1);
      await box.put(s.key, s);
      final back = box.get(s.key)!;
      expect(back.symbol, 'BTCUSDT');
      expect(back.entry, 100);
      expect(back.outcome, SignalOutcome.slHit);
      expect(back.profitLoss, -1);
      expect(back.schemaVersion, AppConfig.signalSchemaVersion);
      await box.close();
    });
  });
}
