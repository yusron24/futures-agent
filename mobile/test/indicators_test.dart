import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/indicators/indicators.dart';
import 'package:scalp_signals/models/candle.dart';

Candle _c(int t, double o, double h, double l, double close, double v) => Candle(
      openTime: t,
      open: o,
      high: h,
      low: l,
      close: close,
      volume: v,
      closeTime: t + 3599999,
    );

List<Candle> _series(List<double> closes) {
  final out = <Candle>[];
  for (int i = 0; i < closes.length; i++) {
    final c = closes[i];
    final prev = i == 0 ? c : closes[i - 1];
    out.add(_c(i * 3600000, prev, math.max(prev, c) * 1.001,
        math.min(prev, c) * 0.999, c, 100 + i.toDouble()));
  }
  return out;
}

void main() {
  group('Indicators', () {
    test('SMA computes trailing average', () {
      final sma = Indicators.sma([1, 2, 3, 4, 5], 3);
      expect(sma[0].isNaN, true);
      expect(sma[1].isNaN, true);
      expect(sma[2], closeTo(2, 1e-9));
      expect(sma[4], closeTo(4, 1e-9));
    });

    test('EMA converges and reacts faster than SMA', () {
      final src = List<double>.generate(50, (i) => 100 + i.toDouble());
      final ema = Indicators.ema(src, 10);
      expect(ema.last.isNaN, false);
      // Untuk seri naik linear, EMA < harga terakhir tapi mendekati.
      expect(ema.last, lessThan(src.last));
      expect(ema.last, greaterThan(src.last - 15));
    });

    test('RSI bounded 0..100 and high for uptrend', () {
      final src = List<double>.generate(40, (i) => 100 + i.toDouble());
      final rsi = Indicators.rsi(src, 14);
      expect(rsi.last, greaterThan(90));
      expect(rsi.last, lessThanOrEqualTo(100));
    });

    test('MACD histogram = macd - signal where valid', () {
      final src = List<double>.generate(
          100, (i) => 100 + 10 * math.sin(i / 5).toDouble());
      final m = Indicators.macd(src);
      for (int i = 0; i < src.length; i++) {
        if (!m.histogram[i].isNaN) {
          expect(m.histogram[i], closeTo(m.macd[i] - m.signal[i], 1e-9));
        }
      }
    });

    test('Bollinger bands ordered upper>=mid>=lower', () {
      final src = List<double>.generate(
          60, (i) => 100 + 5 * math.sin(i / 3).toDouble());
      final bb = Indicators.bollinger(src, period: 20, mult: 2);
      for (int i = 20; i < src.length; i++) {
        expect(bb.upper[i], greaterThanOrEqualTo(bb.middle[i]));
        expect(bb.middle[i], greaterThanOrEqualTo(bb.lower[i]));
      }
    });

    test('ATR positive', () {
      final s = _series(List<double>.generate(40, (i) => 100 + i.toDouble()));
      final atr = Indicators.atr(s, 14);
      expect(atr.last, greaterThan(0));
    });

    test('Stochastic bounded 0..100', () {
      final s = _series(List<double>.generate(
          60, (i) => 100 + 10 * math.sin(i / 4).toDouble()));
      final st = Indicators.stochastic(s);
      final k = st.k.where((v) => !v.isNaN);
      expect(k.every((v) => v >= 0 && v <= 100), true);
    });

    test('Volume profile POC within range', () {
      final s = _series(List<double>.generate(50, (i) => 100 + (i % 5)));
      final vp = Indicators.volumeProfile(s, bins: 20);
      expect(vp.poc, greaterThanOrEqualTo(vp.low));
      expect(vp.poc, lessThanOrEqualTo(vp.high));
    });

    test('Bullish engulfing detection', () {
      final prev = _c(0, 10, 10.2, 9.5, 9.6, 100); // bearish
      final cur = _c(1, 9.5, 10.6, 9.4, 10.5, 120); // bullish engulf
      expect(Indicators.isBullishEngulfing(prev, cur), true);
    });
  });
}
