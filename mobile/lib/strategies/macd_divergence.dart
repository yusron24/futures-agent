import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 3 — Divergensi MACD (swing 4 jam).
///
/// - MACD (12,26,9).
/// - Bullish: harga membentuk lower low, histogram MACD membentuk higher low
///   (divergensi). Entry setelah histogram mulai naik.
/// - SL: sedikit di bawah lower low (−0,2%); TP = 2,5×SL.
/// - Batal bila jarak SL >4% dari entry.
/// - Bearish = kebalikannya.
class MacdDivergence extends Strategy {
  @override
  String get id => 'macd_divergence';
  @override
  String get name => 'Divergensi MACD';
  @override
  String get description =>
      'Divergensi harga vs histogram MACD(12,26,9) dgn konfirmasi histogram '
      'berbalik. RR tetap 1:2,5.';
  @override
  int get minCandles => 120;

  static const double slBufferPct = 0.002; // 0,2%
  static const double maxSlPct = 0.04; // 4%
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final macd = Indicators.macd(closes);
    final hist = macd.histogram;

    final last = candles.length - 1;
    final entry = candles[last].close;
    if (hist[last].isNaN || hist[last - 1].isNaN) {
      return StrategyResult.none(id, name);
    }

    final lows = Indicators.swingLows(candles, left: 2, right: 2);
    final highs = Indicators.swingHighs(candles, left: 2, right: 2);

    // --- Divergensi bullish ---
    if (lows.length >= 2) {
      final i1 = lows[lows.length - 2];
      final i2 = lows[lows.length - 1];
      final priceLowerLow = candles[i2].low < candles[i1].low;
      final histHigherLow = !hist[i1].isNaN &&
          !hist[i2].isNaN &&
          hist[i2] > hist[i1];
      final histRising = hist[last] > hist[last - 1];
      if (priceLowerLow && histHigherLow && histRising) {
        final sl = candles[i2].low * (1 - slBufferPct);
        final risk = entry - sl;
        if (risk > 0 && risk / entry <= maxSlPct) {
          final tp = entry + rr * risk;
          return StrategyResult(
            strategyId: id,
            strategyName: name,
            fired: true,
            direction: TradeDirection.buy,
            confidence: _confidence(hist[i2] - hist[i1]),
            entry: entry,
            stopLoss: sl,
            takeProfit: tp,
            indicators: {
              'Histogram': hist[last].toStringAsFixed(5),
              'MACD': macd.macd[last].toStringAsFixed(5),
              'RR': '1:2,5',
            },
            note: 'Divergensi bullish MACD (harga LL, histogram HL)',
          );
        }
      }
    }

    // --- Divergensi bearish ---
    if (highs.length >= 2) {
      final i1 = highs[highs.length - 2];
      final i2 = highs[highs.length - 1];
      final priceHigherHigh = candles[i2].high > candles[i1].high;
      final histLowerHigh = !hist[i1].isNaN &&
          !hist[i2].isNaN &&
          hist[i2] < hist[i1];
      final histFalling = hist[last] < hist[last - 1];
      if (priceHigherHigh && histLowerHigh && histFalling) {
        final sl = candles[i2].high * (1 + slBufferPct);
        final risk = sl - entry;
        if (risk > 0 && risk / entry <= maxSlPct) {
          final tp = entry - rr * risk;
          return StrategyResult(
            strategyId: id,
            strategyName: name,
            fired: true,
            direction: TradeDirection.sell,
            confidence: _confidence(hist[i1] - hist[i2]),
            entry: entry,
            stopLoss: sl,
            takeProfit: tp,
            indicators: {
              'Histogram': hist[last].toStringAsFixed(5),
              'MACD': macd.macd[last].toStringAsFixed(5),
              'RR': '1:2,5',
            },
            note: 'Divergensi bearish MACD (harga HH, histogram LH)',
          );
        }
      }
    }

    return StrategyResult.none(id, name, note: 'Tanpa divergensi MACD valid');
  }

  double _confidence(double gap) {
    double c = 55;
    c += (gap.abs() * 500).clamp(0, 30);
    return c.clamp(0, 100);
  }
}
