import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 5 — MA Crossover + ADX (swing 4 jam).
///
/// - EMA20 & EMA50. Golden cross (EMA20 memotong EMA50 ke atas) + ADX(14)>25
///   dan harga di atas EMA200 → LONG. Death cross + ADX>25 dan harga di bawah
///   EMA200 → SHORT.
/// - SL: 1,5×ATR di bawah/atas low/high candle crossover; TP = 2,5×SL.
class MaCrossoverAdx extends Strategy {
  @override
  String get id => 'ma_crossover_adx';
  @override
  String get name => 'MA Crossover + ADX';
  @override
  String get description =>
      'Golden/death cross EMA20-EMA50 disaring ADX>25 & EMA200. RR tetap 1:2,5.';
  @override
  int get minCandles => 230;

  static const int fast = 20;
  static const int slow = 50;
  static const int trendPeriod = 200;
  static const int adxPeriod = 14;
  static const int atrPeriod = 14;
  static const double adxThreshold = 25;
  static const double atrMult = 1.5;
  static const int crossLookback = 4; // candle terakhir untuk mendeteksi cross
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final emaFast = Indicators.ema(closes, fast);
    final emaSlow = Indicators.ema(closes, slow);
    final emaTrend = Indicators.ema(closes, trendPeriod);
    final adxRes = Indicators.adx(candles, period: adxPeriod);
    final atr = Indicators.atr(candles, atrPeriod);

    final last = candles.length - 1;
    final entry = candles[last].close;
    if (emaFast[last].isNaN ||
        emaSlow[last].isNaN ||
        emaTrend[last].isNaN ||
        adxRes.adx[last].isNaN ||
        atr[last].isNaN) {
      return StrategyResult.none(id, name);
    }
    if (adxRes.adx[last] < adxThreshold) {
      return StrategyResult.none(id, name,
          note: 'ADX ${adxRes.adx[last].toStringAsFixed(0)} <25 (tren lemah)');
    }

    // Cari crossover terbaru dalam beberapa candle terakhir.
    int? crossIdx;
    bool goldenCross = false;
    for (int i = last; i > last - crossLookback && i >= 1; i--) {
      if (emaFast[i].isNaN || emaSlow[i].isNaN ||
          emaFast[i - 1].isNaN || emaSlow[i - 1].isNaN) {
        continue;
      }
      final prevDiff = emaFast[i - 1] - emaSlow[i - 1];
      final curDiff = emaFast[i] - emaSlow[i];
      if (prevDiff <= 0 && curDiff > 0) {
        crossIdx = i;
        goldenCross = true;
        break;
      }
      if (prevDiff >= 0 && curDiff < 0) {
        crossIdx = i;
        goldenCross = false;
        break;
      }
    }
    if (crossIdx == null) {
      return StrategyResult.none(id, name, note: 'Tanpa crossover terbaru');
    }

    if (goldenCross) {
      if (entry <= emaTrend[last]) {
        return StrategyResult.none(id, name,
            note: 'Harga di bawah EMA200 (filter tren)');
      }
      final sl = candles[crossIdx].low - atrMult * atr[last];
      final risk = entry - sl;
      if (risk <= 0) return StrategyResult.none(id, name);
      final tp = entry + rr * risk;
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.buy,
        confidence: _confidence(adxRes.adx[last]),
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: {
          'EMA20/50': '${emaFast[last].toStringAsFixed(4)} / '
              '${emaSlow[last].toStringAsFixed(4)}',
          'ADX(14)': adxRes.adx[last].toStringAsFixed(1),
          'EMA200': emaTrend[last].toStringAsFixed(4),
          'RR': '1:2,5',
        },
        note: 'Golden cross EMA20>EMA50 + ADX kuat',
      );
    } else {
      if (entry >= emaTrend[last]) {
        return StrategyResult.none(id, name,
            note: 'Harga di atas EMA200 (filter tren)');
      }
      final sl = candles[crossIdx].high + atrMult * atr[last];
      final risk = sl - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final tp = entry - rr * risk;
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.sell,
        confidence: _confidence(adxRes.adx[last]),
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: {
          'EMA20/50': '${emaFast[last].toStringAsFixed(4)} / '
              '${emaSlow[last].toStringAsFixed(4)}',
          'ADX(14)': adxRes.adx[last].toStringAsFixed(1),
          'EMA200': emaTrend[last].toStringAsFixed(4),
          'RR': '1:2,5',
        },
        note: 'Death cross EMA20<EMA50 + ADX kuat',
      );
    }
  }

  double _confidence(double adx) {
    double c = 55;
    c += ((adx - adxThreshold) * 1.2).clamp(0, 30);
    return c.clamp(0, 100);
  }
}
