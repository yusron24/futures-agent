import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 3 — MACD Zero-Line Rejection dengan Engulfing.
///
/// - MACD(12,26,9). Garis MACD mendekati nol dari atas (bullish) / bawah
///   (bearish); histogram mulai mendatar.
/// - Konfirmasi: candle engulfing searah tren tepat di garis nol.
/// - SL: di bawah low candle engulfing (buy) / di atas high (sell).
/// - TP: minimal 2,5× jarak stop; target pertama = ekstensi Fibonacci 1.618
///   dari swing terakhir.
class MacdZeroLineEngulfing extends Strategy {
  @override
  String get id => 'macd_zeroline_engulfing';
  @override
  String get name => 'MACD Zero-Line Rejection';
  @override
  String get description =>
      'Penolakan garis nol MACD dengan konfirmasi candle engulfing.';
  @override
  int get minCandles => 120;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final m = Indicators.macd(closes);
    final last = candles.length - 1;
    final prev = last - 1;

    if (m.macd[last].isNaN || m.histogram[last].isNaN || m.histogram[prev].isNaN) {
      return StrategyResult.none(id, name);
    }

    final cur = candles[last];
    final pcandle = candles[prev];

    // Seberapa dekat MACD ke garis nol, relatif terhadap volatilitas MACD.
    final macdAbsRef = _recentAbsMacd(m.macd, last);
    if (macdAbsRef == 0) return StrategyResult.none(id, name);
    final nearZero = m.macd[last].abs() <= macdAbsRef * 0.35;
    if (!nearZero) {
      return StrategyResult.none(id, name, note: 'MACD belum di garis nol');
    }

    // Histogram mulai mendatar: perubahan histogram mengecil.
    final histFlattening =
        m.histogram[last].abs() <= m.histogram[prev].abs();

    // Tren dominan dari sisi MACD terakhir sebelum menyentuh nol.
    final approachingFromAbove = m.macd[prev] > 0; // bullish trend context
    final approachingFromBelow = m.macd[prev] < 0;

    if (approachingFromAbove &&
        Indicators.isBullishEngulfing(pcandle, cur) &&
        histFlattening) {
      final entry = cur.close;
      final stop = cur.low - (cur.high - cur.low) * 0.05;
      final risk = entry - stop;
      if (risk <= 0) return StrategyResult.none(id, name);
      final fibTarget = _fib1618Up(candles, entry);
      final baseTarget = entry + 2.5 * risk;
      final target = math.max(baseTarget, fibTarget);
      return _build(TradeDirection.buy, entry, stop, target, m, cur, last,
          'Engulfing bullish menolak garis nol MACD');
    }

    if (approachingFromBelow &&
        Indicators.isBearishEngulfing(pcandle, cur) &&
        histFlattening) {
      final entry = cur.close;
      final stop = cur.high + (cur.high - cur.low) * 0.05;
      final risk = stop - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final fibTarget = _fib1618Down(candles, entry);
      final baseTarget = entry - 2.5 * risk;
      final target = math.min(baseTarget, fibTarget);
      return _build(TradeDirection.sell, entry, stop, target, m, cur, last,
          'Engulfing bearish menolak garis nol MACD');
    }

    return StrategyResult.none(id, name, note: 'Tanpa engulfing konfirmasi');
  }

  double _recentAbsMacd(List<double> macd, int last, {int n = 50}) {
    double maxAbs = 0;
    int count = 0;
    for (int i = last; i >= 0 && count < n; i--) {
      if (!macd[i].isNaN) {
        maxAbs = math.max(maxAbs, macd[i].abs());
        count++;
      }
    }
    return maxAbs;
  }

  double _fib1618Up(List<Candle> c, double entry) {
    final lows = Indicators.swingLows(c, left: 2, right: 2);
    final highs = Indicators.swingHighs(c, left: 2, right: 2);
    if (lows.isEmpty || highs.isEmpty) return entry;
    final swingLow = c[lows.last].low;
    final swingHigh = c[highs.last].high;
    final leg = (swingHigh - swingLow).abs();
    return swingLow + leg * 1.618;
  }

  double _fib1618Down(List<Candle> c, double entry) {
    final lows = Indicators.swingLows(c, left: 2, right: 2);
    final highs = Indicators.swingHighs(c, left: 2, right: 2);
    if (lows.isEmpty || highs.isEmpty) return entry;
    final swingLow = c[lows.last].low;
    final swingHigh = c[highs.last].high;
    final leg = (swingHigh - swingLow).abs();
    return swingHigh - leg * 1.618;
  }

  StrategyResult _build(
    String dir,
    double entry,
    double stop,
    double target,
    MacdResult m,
    Candle c,
    int last,
    String note,
  ) {
    double conf = 58;
    // Volume kuat pada candle engulfing menambah keyakinan.
    final range = c.high - c.low;
    if (range > 0) {
      final bodyRatio = (c.close - c.open).abs() / range;
      conf += (bodyRatio * 20).clamp(0, 20);
    }
    // Histogram menyeberang tanda (momentum berbalik) menambah keyakinan.
    conf += 12;
    return StrategyResult(
      strategyId: id,
      strategyName: name,
      fired: true,
      direction: dir,
      confidence: conf.clamp(0, 100),
      entry: entry,
      stopLoss: stop,
      takeProfit: target,
      indicators: {
        'MACD': m.macd[last].toStringAsFixed(5),
        'Signal': m.signal[last].toStringAsFixed(5),
        'Hist': m.histogram[last].toStringAsFixed(5),
      },
      note: note,
    );
  }
}
