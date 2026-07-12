import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/models/strategy_result.dart';
import 'package:scalp_signals/strategies/fib_retracement_stochastic.dart';
import 'package:scalp_signals/strategies/strategy_registry.dart';

const int _swingLowIdx = 65;
const int _swingHighIdx = 100;

// Base: turun 112→100 (0..65, swing low), impuls 100→140 (66..100, swing high),
// retrace 140→110 (101..123). Tail 6 candle ditentukan tiap test.
List<double> _base() {
  final c = <double>[];
  for (int i = 0; i <= 65; i++) {
    c.add(112 - (112 - 100) * (i / 65));
  }
  for (int i = 66; i <= 100; i++) {
    c.add(100 + 40 * ((i - 66) / 34));
  }
  for (int i = 101; i <= 123; i++) {
    c.add(140 - (140 - 110) * ((i - 101) / 22));
  }
  return c; // 124 candle (0..123)
}

List<Candle> _mk(List<double> closes, {double lastVol = 100}) {
  final out = <Candle>[];
  for (int i = 0; i < closes.length; i++) {
    final c = closes[i];
    final o = i == 0 ? c : closes[i - 1];
    var hi = (c > o ? c : o) + 0.15;
    var lo = (c < o ? c : o) - 0.15;
    if (i == _swingLowIdx) lo -= 2.0; // wick tajam → pivot low unik
    if (i == _swingHighIdx) hi += 2.0; // wick tajam → pivot high unik
    out.add(Candle(
      openTime: i * 3600000,
      open: o,
      high: hi,
      low: lo,
      close: c,
      volume: i == closes.length - 1 ? lastVol : 100.0,
      closeTime: i * 3600000 + 1,
    ));
  }
  return out;
}

// Tail: close tinggi (113) mengangkat D, lalu K tertekan di dasar (109.9),
// kemudian uptick tegas (111.5) → crossover bullish segar saat oversold, di
// dalam zona Fib 0.618–0.786.
final _validTail = <double>[113.0, 109.9, 109.9, 109.9, 109.9, 111.5];
// Tail lanjut turun (tanpa crossover).
final _noReboundTail = <double>[110.0, 109.9, 109.8, 109.7, 109.6, 109.4];

void main() {
  group('FibRetracementStochastic', () {
    test('terdaftar sebagai strategi ke-7', () {
      expect(StrategyRegistry.allIds.contains('fib_retracement_stochastic'),
          true);
      expect(StrategyRegistry.all.length, 7);
    });

    test('data kurang → tidak fired', () {
      final s = FibRetracementStochastic();
      final few = List.generate(
          60,
          (i) => Candle(
              openTime: i * 3600000,
              open: 100,
              high: 101,
              low: 99,
              close: 100,
              volume: 10,
              closeTime: i * 3600000 + 1));
      expect(s.evaluate('BTCUSDT', few).fired, false);
    });

    test('setup valid → fired BUY dengan RR 1:2,5', () {
      final s = FibRetracementStochastic();
      final r = s.evaluate('BTCUSDT', _mk([..._base(), ..._validTail]));
      expect(r.fired, true);
      expect(r.direction, TradeDirection.buy);
      expect(r.riskReward, closeTo(2.5, 1e-6));
      expect(r.stopLoss, lessThan(r.entry));
      expect(r.takeProfit, greaterThan(r.entry));
      expect(r.confidence, greaterThan(0));
    });

    test('tanpa retracement dalam (harga di atas zona) → tidak fired', () {
      // Retrace dangkal ke 131 (di atas zona 0.618).
      final c = <double>[];
      for (int i = 0; i <= 65; i++) {
        c.add(112 - (112 - 100) * (i / 65));
      }
      for (int i = 66; i <= 100; i++) {
        c.add(100 + 40 * ((i - 66) / 34));
      }
      for (int i = 101; i <= 129; i++) {
        c.add(140 - (140 - 131) * ((i - 101) / 28));
      }
      final s = FibRetracementStochastic();
      expect(s.evaluate('BTCUSDT', _mk(c)).fired, false);
    });

    test('tanpa rebound stochastic (lanjut turun) → tidak fired', () {
      final s = FibRetracementStochastic();
      final r = s.evaluate('BTCUSDT', _mk([..._base(), ..._noReboundTail]));
      expect(r.fired, false);
    });

    test('volume surge menaikkan confidence', () {
      final s = FibRetracementStochastic();
      final base = s.evaluate('BTCUSDT', _mk([..._base(), ..._validTail]));
      final surge = s.evaluate(
          'BTCUSDT', _mk([..._base(), ..._validTail], lastVol: 500));
      expect(base.fired, true);
      expect(surge.fired, true);
      expect(surge.confidence, greaterThan(base.confidence));
    });
  });
}
