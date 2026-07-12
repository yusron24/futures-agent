import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/signal.dart';
import 'package:scalp_signals/signals/paper_account.dart';

Signal _resolved({
  required String outcome,
  required double profitLoss,
  required int resolvedAt,
  double entry = 100,
  double stop = 98,
}) =>
    Signal(
      symbol: 'BTCUSDT',
      direction: 'BUY',
      entry: entry,
      stopLoss: stop,
      takeProfit: entry + 2.5 * (entry - stop),
      confidence: 80,
      riskReward: 2.5,
      triggeredStrategies: const ['a'],
      timestamp: resolvedAt - 1,
      outcome: outcome,
      resolvedAt: resolvedAt,
      profitLoss: profitLoss,
    );

void main() {
  group('PaperAccount.summarize', () {
    final signals = [
      _resolved(outcome: SignalOutcome.tpHit, profitLoss: 2.5, resolvedAt: 2),
      _resolved(outcome: SignalOutcome.slHit, profitLoss: -1.0, resolvedAt: 1),
      // pending diabaikan:
      _resolved(outcome: SignalOutcome.pending, profitLoss: 0, resolvedAt: 3),
    ];

    test('tanpa biaya: saldo = start + Σ(risk×R)', () {
      final s = PaperAccount.summarize(signals,
          startCapital: 1000, riskAmount: 10, applyCost: false);
      expect(s.trades, 2);
      expect(s.wins, 1);
      expect(s.losses, 1);
      // urut waktu: SL(−1→−10) lalu TP(+2,5→+25) → 1000−10+25 = 1015
      expect(s.balance, closeTo(1015, 1e-9));
      expect(s.netExpectancyR, closeTo(0.75, 1e-9));
    });

    test('dengan biaya: saldo lebih rendah & PF net < PF gross', () {
      final net = PaperAccount.summarize(signals,
          startCapital: 1000, riskAmount: 10, applyCost: true);
      final gross = PaperAccount.summarize(signals,
          startCapital: 1000, riskAmount: 10, applyCost: false);
      expect(net.balance, lessThan(gross.balance));
      expect(net.netExpectancyR, lessThan(gross.netExpectancyR));
      expect(net.totalCostR, greaterThan(0));
      expect(net.netProfitFactor!, lessThan(gross.netProfitFactor!));
    });

    test('equity curve panjang = trades + 1, dimulai dari modal', () {
      final s = PaperAccount.summarize(signals,
          startCapital: 1000, riskAmount: 10);
      expect(s.equityCurve.length, s.trades + 1);
      expect(s.equityCurve.first, 1000);
    });

    test('tanpa trade selesai → summary kosong', () {
      final s = PaperAccount.summarize(
        [_resolved(outcome: SignalOutcome.pending, profitLoss: 0, resolvedAt: 1)],
        startCapital: 1000,
        riskAmount: 10,
      );
      expect(s.trades, 0);
      expect(s.balance, 1000);
      expect(s.equityCurve, [1000]);
      expect(s.netProfitFactor, isNull);
    });
  });
}
