import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/models/signal.dart';
import 'package:scalp_signals/signals/trade_simulator.dart';

Candle _c(int openTime, double high, double low) => Candle(
      openTime: openTime,
      open: (high + low) / 2,
      high: high,
      low: low,
      close: (high + low) / 2,
      volume: 100,
      closeTime: openTime + 1,
    );

void main() {
  group('simulateTradeOutcome', () {
    test('BUY: TP tersentuh → tpHit', () {
      final r = simulateTradeOutcome(
        isBuy: true,
        stopLoss: 95,
        takeProfit: 110,
        afterTs: 0,
        candles: [_c(10, 111, 96)],
      );
      expect(r.outcome, SignalOutcome.tpHit);
      expect(r.resolvedAt, 11);
      expect(r.index, 0);
    });

    test('BUY: SL tersentuh → slHit', () {
      final r = simulateTradeOutcome(
        isBuy: true,
        stopLoss: 95,
        takeProfit: 110,
        afterTs: 0,
        candles: [_c(10, 100, 94)],
      );
      expect(r.outcome, SignalOutcome.slHit);
    });

    test('GUARDRAIL: TP & SL di candle yang SAMA → SL (konservatif)', () {
      final r = simulateTradeOutcome(
        isBuy: true,
        stopLoss: 95,
        takeProfit: 110,
        afterTs: 0,
        candles: [_c(10, 111, 94)], // high≥TP dan low≤SL
      );
      expect(r.outcome, SignalOutcome.slHit);
    });

    test('tidak tersentuh → pending (null)', () {
      final r = simulateTradeOutcome(
        isBuy: true,
        stopLoss: 95,
        takeProfit: 110,
        afterTs: 0,
        candles: [_c(10, 100, 96)],
      );
      expect(r.outcome, isNull);
      expect(r.index, -1);
    });

    test('melewati candle dengan openTime ≤ afterTs', () {
      final r = simulateTradeOutcome(
        isBuy: true,
        stopLoss: 95,
        takeProfit: 110,
        afterTs: 100,
        candles: [_c(50, 111, 96), _c(150, 111, 96)], // yg pertama dilewati
      );
      expect(r.outcome, SignalOutcome.tpHit);
      expect(r.resolvedAt, 151);
    });

    test('SELL: SL (high≥stop) & TP (low≤tp) — arah terbalik', () {
      final sl = simulateTradeOutcome(
        isBuy: false,
        stopLoss: 110,
        takeProfit: 95,
        afterTs: 0,
        candles: [_c(10, 111, 100)],
      );
      expect(sl.outcome, SignalOutcome.slHit);

      final tp = simulateTradeOutcome(
        isBuy: false,
        stopLoss: 110,
        takeProfit: 95,
        afterTs: 0,
        candles: [_c(10, 108, 94)],
      );
      expect(tp.outcome, SignalOutcome.tpHit);
    });
  });
}
