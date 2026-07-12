import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:scalp_signals/data/settings_repository.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/signals/backtest_engine.dart';

void main() {
  group('InMemoryStats (meniru live: shrinkage + decay + cooldown)', () {
    test('akurasi awal = prior 0,5; menang menaikkan, kalah menurunkan', () {
      final s = InMemoryStats();
      expect(s.calibratedAccuracy('x'), closeTo(0.5, 1e-9));
      s.recordOutcome(['x'], true);
      expect(s.calibratedAccuracy('x'), greaterThan(0.5));
      final s2 = InMemoryStats();
      for (int i = 0; i < 5; i++) {
        s2.recordOutcome(['y'], false);
      }
      expect(s2.calibratedAccuracy('y'), lessThan(0.5));
    });

    test('cooldown: inCooldown benar terhadap nowMs & per-simbol', () {
      final s = InMemoryStats();
      s.setCooldown('BTCUSDT', 1000);
      expect(s.inCooldown('BTCUSDT', 999), true);
      expect(s.inCooldown('BTCUSDT', 1000), false);
      expect(s.inCooldown('ETHUSDT', 999), false);
    });
  });

  group('BacktestReport.fromTrades (agregasi net; gross terpisah)', () {
    final trades = [
      const BacktestTrade(
          timestamp: 1,
          direction: 'BUY',
          strategies: ['a'],
          regime: 'Tren Naik',
          grossR: 2.5,
          costR: 0.1,
          netR: 2.4,
          win: true),
      const BacktestTrade(
          timestamp: 2,
          direction: 'BUY',
          strategies: ['a', 'b'],
          regime: 'Sideways',
          grossR: -1.0,
          costR: 0.05,
          netR: -1.05,
          win: false),
      const BacktestTrade(
          timestamp: 3,
          direction: 'BUY',
          strategies: ['b'],
          regime: 'Tren Naik',
          grossR: 2.5,
          costR: 0.1,
          netR: 2.4,
          win: true),
    ];

    test('metrik agregat net & gross', () {
      final r = BacktestReport.fromTrades('BTCUSDT', trades);
      expect(r.totalTrades, 3);
      expect(r.wins, 2);
      expect(r.losses, 1);
      expect(r.winRate, closeTo(66.6667, 1e-3));
      expect(r.grossExpectancyR, closeTo(4 / 3, 1e-9));
      expect(r.netExpectancyR, closeTo(1.25, 1e-9));
      expect(r.totalCostR, closeTo(0.25, 1e-9));
      expect(r.netProfitFactor!, closeTo(4.8 / 1.05, 1e-6));
    });

    test('equity curve (kumulatif netR) & max drawdown', () {
      final r = BacktestReport.fromTrades('BTCUSDT', trades);
      expect(r.equityCurveR, [0, closeTo(2.4, 1e-9), closeTo(1.35, 1e-9),
        closeTo(3.75, 1e-9)]);
      expect(r.maxDrawdownR, closeTo(1.05, 1e-9));
    });

    test('atribusi per strategi & per regime', () {
      final r = BacktestReport.fromTrades('BTCUSDT', trades);
      expect(r.perStrategy['a']!.trades, 2);
      expect(r.perStrategy['a']!.wins, 1);
      expect(r.perStrategy['a']!.netR, closeTo(1.35, 1e-9));
      expect(r.perStrategy['b']!.trades, 2);
      expect(r.perRegime['Tren Naik']!.trades, 2);
      expect(r.perRegime['Tren Naik']!.wins, 2);
      expect(r.perRegime['Sideways']!.trades, 1);
    });

    test('kosong → report kosong', () {
      final r = BacktestReport.fromTrades('BTCUSDT', const []);
      expect(r.totalTrades, 0);
      expect(r.winRate, 0);
      expect(r.equityCurveR, [0]);
      expect(r.netProfitFactor, isNull);
    });
  });

  group('BacktestRunner.run (walk-forward, engine sama)', () {
    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('hive_bt_test');
      Hive.init(dir.path);
      await Hive.openBox('settings');
    });

    List<Candle> uptrendWithPullbacks(int n) {
      final rnd = math.Random(3);
      double price = 100;
      final out = <Candle>[];
      const step = 14400000; // 4h
      for (int i = 0; i < n; i++) {
        final noise = (rnd.nextDouble() - 0.5) * 1.2;
        final open = price;
        var close = price + 0.6 + noise; // drift naik
        if (i % 17 == 0) close = price - 1.5; // pullback berkala
        final high = math.max(open, close) + rnd.nextDouble() * 0.8 + 0.2;
        final low = math.min(open, close) - rnd.nextDouble() * 0.8 - 0.2;
        out.add(Candle(
          openTime: i * step,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: 100 + rnd.nextDouble() * 50,
          closeTime: i * step + 1,
        ));
        price = close;
      }
      return out;
    }

    test('replay tak crash & invarian laporan konsisten', () {
      final settings = SettingsRepository();
      final report = BacktestRunner.run(
        symbol: 'BTCUSDT',
        candles: uptrendWithPullbacks(400),
        settings: settings,
      );
      expect(report.symbol, 'BTCUSDT');
      expect(report.equityCurveR.length, report.totalTrades + 1);
      expect(report.winRate, inInclusiveRange(0, 100));
      expect(report.totalTrades, greaterThanOrEqualTo(0));
      if (report.totalTrades > 0) {
        // Net tak pernah melebihi gross (biaya ≥ 0).
        expect(report.netExpectancyR,
            lessThanOrEqualTo(report.grossExpectancyR + 1e-9));
        final regimeTrades =
            report.perRegime.values.fold<int>(0, (a, b) => a + b.trades);
        expect(regimeTrades, report.totalTrades);
      }
    });

    test('data kurang dari minimal → report kosong', () {
      final settings = SettingsRepository();
      final report = BacktestRunner.run(
        symbol: 'BTCUSDT',
        candles: uptrendWithPullbacks(100),
        settings: settings,
      );
      expect(report.totalTrades, 0);
      expect(report.equityCurveR, [0]);
    });
  });
}
