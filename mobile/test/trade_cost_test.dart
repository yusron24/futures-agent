import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/signals/trade_cost.dart';

void main() {
  group('TradeCostModel', () {
    test('costInR: contoh pasti (fee 0,04%/sisi + slippage 0,02%, risk 2%)', () {
      // roundTrip = 2*0,0004 + 0,0002 = 0,001 ; riskFrac = 2/100 = 0,02
      // costR = 0,001 / 0,02 = 0,05
      final c = TradeCostModel.costInR(
          entry: 100, stop: 98, feePctPerSide: 0.04, slippagePct: 0.02);
      expect(c, closeTo(0.05, 1e-9));
    });

    test('SL lebih ketat (risk% kecil) → biaya R lebih besar', () {
      final tight = TradeCostModel.costInR(entry: 100, stop: 99); // 1%
      final loose = TradeCostModel.costInR(entry: 100, stop: 98); // 2%
      expect(tight, greaterThan(loose));
    });

    test('input tak valid → 0', () {
      expect(TradeCostModel.costInR(entry: 0, stop: 0), 0);
      expect(TradeCostModel.costInR(entry: 100, stop: 100), 0);
    });

    test('netR = gross − cost', () {
      expect(TradeCostModel.netR(2.5, 0.05), closeTo(2.45, 1e-9));
      expect(TradeCostModel.netR(-1.0, 0.05), closeTo(-1.05, 1e-9));
    });
  });
}
