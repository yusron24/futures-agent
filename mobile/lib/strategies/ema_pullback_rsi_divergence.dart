import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 1 — EMA Pullback + Divergensi RSI.
///
/// - Tren dari kemiringan EMA50 + posisi harga.
/// - Tren naik: harga pullback ke EMA50 (dalam 0,3%) + divergensi bullish RSI
///   (price lower low, RSI higher low). Kebalikannya untuk tren turun.
/// - SL: 0,5% di bawah/atas swing terbaru atau 1,5×ATR (paling lebar).
/// - TP: 2× jarak SL (asimetris minimal 1:2).
class EmaPullbackRsiDivergence extends Strategy {
  @override
  String get id => 'ema_pullback_rsi_div';
  @override
  String get name => 'EMA Pullback + RSI Divergence';
  @override
  String get description =>
      'Pullback ke EMA50 searah tren dengan konfirmasi divergensi RSI(14).';
  @override
  int get minCandles => 120;

  static const int emaPeriod = 50;
  static const int rsiPeriod = 14;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final ema = Indicators.ema(closes, emaPeriod);
    final rsi = Indicators.rsi(closes, rsiPeriod);
    final atr = Indicators.atr(candles, 14);

    final last = candles.length - 1;
    final price = candles[last].close;
    final emaNow = ema[last];
    final emaPrev = ema[last - 5];
    if (emaNow.isNaN || emaPrev.isNaN || atr[last].isNaN) {
      return StrategyResult.none(id, name);
    }

    final slope = (emaNow - emaPrev) / emaPrev; // kemiringan relatif
    final distToEma = (price - emaNow).abs() / emaNow;
    final nearEma = distToEma <= 0.003; // dalam 0,3%

    // Uptrend: harga di atas EMA & EMA naik.
    final uptrend = price > emaNow && slope > 0.0005;
    final downtrend = price < emaNow && slope < -0.0005;

    if (!nearEma || (!uptrend && !downtrend)) {
      return StrategyResult.none(id, name, note: 'Belum pullback ke EMA');
    }

    // Cari dua swing terakhir untuk mengukur divergensi.
    if (uptrend) {
      final lows = Indicators.swingLows(candles, left: 2, right: 2);
      if (lows.length < 2) return StrategyResult.none(id, name);
      final i1 = lows[lows.length - 2];
      final i2 = lows[lows.length - 1];
      final priceLowerLow = candles[i2].low < candles[i1].low;
      final rsiHigherLow = !rsi[i1].isNaN &&
          !rsi[i2].isNaN &&
          rsi[i2] > rsi[i1];
      if (!(priceLowerLow && rsiHigherLow)) {
        return StrategyResult.none(id, name, note: 'Tanpa divergensi bullish');
      }

      final swingLow = candles[i2].low;
      final slByPct = swingLow * (1 - 0.005);
      final slByAtr = price - 1.5 * atr[last];
      final stop = math.min(slByPct, slByAtr); // paling lebar (paling rendah)
      final risk = price - stop;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = price + 2 * risk;

      final confidence = _confidence(
        divergenceGap: (rsi[i2] - rsi[i1]),
        volumeShrink: _pullbackVolumeShrinks(candles, i2, last),
        slopeStrength: slope.abs(),
      );
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.buy,
        confidence: confidence,
        entry: price,
        stopLoss: stop,
        takeProfit: target,
        indicators: {
          'EMA50': emaNow.toStringAsFixed(4),
          'RSI(14)': rsi[last].toStringAsFixed(1),
          'Slope': (slope * 100).toStringAsFixed(2) + '%',
          'ATR': atr[last].toStringAsFixed(4),
        },
        note: 'Pullback bullish ke EMA50 + divergensi RSI',
      );
    } else {
      final highs = Indicators.swingHighs(candles, left: 2, right: 2);
      if (highs.length < 2) return StrategyResult.none(id, name);
      final i1 = highs[highs.length - 2];
      final i2 = highs[highs.length - 1];
      final priceHigherHigh = candles[i2].high > candles[i1].high;
      final rsiLowerHigh = !rsi[i1].isNaN &&
          !rsi[i2].isNaN &&
          rsi[i2] < rsi[i1];
      if (!(priceHigherHigh && rsiLowerHigh)) {
        return StrategyResult.none(id, name, note: 'Tanpa divergensi bearish');
      }

      final swingHigh = candles[i2].high;
      final slByPct = swingHigh * (1 + 0.005);
      final slByAtr = price + 1.5 * atr[last];
      final stop = math.max(slByPct, slByAtr);
      final risk = stop - price;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = price - 2 * risk;

      final confidence = _confidence(
        divergenceGap: (rsi[i1] - rsi[i2]),
        volumeShrink: _pullbackVolumeShrinks(candles, i2, last),
        slopeStrength: slope.abs(),
      );
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.sell,
        confidence: confidence,
        entry: price,
        stopLoss: stop,
        takeProfit: target,
        indicators: {
          'EMA50': emaNow.toStringAsFixed(4),
          'RSI(14)': rsi[last].toStringAsFixed(1),
          'Slope': (slope * 100).toStringAsFixed(2) + '%',
          'ATR': atr[last].toStringAsFixed(4),
        },
        note: 'Pullback bearish ke EMA50 + divergensi RSI',
      );
    }
  }

  bool _pullbackVolumeShrinks(List<Candle> c, int from, int to) {
    if (to - from < 2) return false;
    return c[to].volume < c[from].volume;
  }

  double _confidence({
    required double divergenceGap,
    required bool volumeShrink,
    required double slopeStrength,
  }) {
    double conf = 55;
    conf += divergenceGap.clamp(0, 20); // divergensi RSI lebih jelas -> +
    if (volumeShrink) conf += 10; // volume pullback menurun -> +
    conf += (slopeStrength * 1000).clamp(0, 15); // tren lebih kuat -> +
    return conf.clamp(0, 100);
  }
}
