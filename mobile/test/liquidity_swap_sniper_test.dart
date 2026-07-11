import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/indicators/vwap.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/models/strategy_result.dart';
import 'package:scalp_signals/strategies/liquidity_swap_sniper_entry.dart';
import 'package:scalp_signals/strategies/strategy_registry.dart';

Candle _c(int i, double o, double h, double l, double c, double v) => Candle(
      openTime: i * 14400000,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v,
      closeTime: i * 14400000 + 1,
    );

void main() {
  group('LiquiditySwapSniperEntry', () {
    test('terdaftar sebagai strategi ke-6 (paralel, tanpa mengubah lama)', () {
      expect(StrategyRegistry.allIds.contains('liquidity_swap_sniper'), true);
      expect(StrategyRegistry.all.length, 6);
    });

    test('data kurang → tidak menghasilkan sinyal', () {
      final s = LiquiditySwapSniperEntry();
      final few = List.generate(50, (i) => _c(i, 100, 101, 99, 100, 10));
      expect(s.evaluate('BTCUSDT', few).fired, false);
    });

    test('seri panjang acak → tidak crash & output konsisten', () {
      // Isolasi logika SMC murni (matikan konfluens VWAP untuk assertion skor).
      VwapConfig.enabledForSignals = false;
      addTearDown(() => VwapConfig.enabledForSignals = true);
      final s = LiquiditySwapSniperEntry();
      final rnd = math.Random(7);
      double price = 100;
      final list = <Candle>[];
      for (int i = 0; i < 300; i++) {
        final ch = (rnd.nextDouble() - 0.5) * 2 + 0.05; // sedikit uptrend
        final open = price;
        final close = price + ch;
        final high = math.max(open, close) + rnd.nextDouble();
        final low = math.min(open, close) - rnd.nextDouble();
        list.add(_c(i, open, high, low, close, 10 + rnd.nextDouble() * 10));
        price = close;
      }
      final r = s.evaluate('BTCUSDT', list);
      expect(r, isA<StrategyResult>());
      // Bila strategi menyala, output harus valid & RR terjaga (~2,5).
      if (r.fired) {
        expect(
          r.direction == TradeDirection.buy ||
              r.direction == TradeDirection.sell,
          true,
        );
        expect(r.riskReward, greaterThan(2.4));
        expect(r.confidence, greaterThanOrEqualTo(75));
        expect(r.entry, greaterThan(0));
        expect(r.stopLoss, greaterThan(0));
        expect(r.takeProfit, greaterThan(0));
      }
    });
  });
}
