import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 5 — Stochastic Overbought/Oversold Reversal dengan Pin Bar.
///
/// - Stochastic(14,3,3). Overbought > 80, Oversold < 20.
/// - Pin bar / enguljng arah berlawanan saat Stochastic ekstrem.
/// - Sumbu menembus support/resistance terdekat (high/low candle sebelumnya).
/// - SL: di luar ekstrem sumbu + 0,2%.
/// - TP: 2,5× jarak stop (atau sampai garis tengah 50 Stochastic).
class StochasticPinBarReversal extends Strategy {
  @override
  String get id => 'stoch_pinbar_reversal';
  @override
  String get name => 'Stochastic Pin Bar Reversal';
  @override
  String get description =>
      'Pembalikan dari area ekstrem Stochastic dengan pin bar / engulfing.';
  @override
  int get minCandles => 60;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final stoch = Indicators.stochastic(candles);
    final rsi = Indicators.rsi(Indicators.closes(candles), 14);
    final last = candles.length - 1;
    final prev = last - 1;
    if (stoch.k[last].isNaN || stoch.k[prev].isNaN) {
      return StrategyResult.none(id, name);
    }

    final cur = candles[last];
    final pcandle = candles[prev];
    final kPrev = stoch.k[prev];

    // Oversold reversal -> BUY.
    final oversoldContext = kPrev < 20;
    final overboughtContext = kPrev > 80;

    final bullReversal = Indicators.isBullishPinBar(cur) ||
        Indicators.isBullishEngulfing(pcandle, cur);
    final bearReversal = Indicators.isBearishPinBar(cur) ||
        Indicators.isBearishEngulfing(pcandle, cur);

    if (oversoldContext && bullReversal && cur.low < pcandle.low) {
      // Sumbu menembus support terdekat (low candle sebelumnya).
      final entry = cur.close;
      final stop = cur.low * (1 - 0.002);
      final risk = entry - stop;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = entry + 2.5 * risk;
      final divergence = _bullDivergence(candles, rsi);
      return _build(TradeDirection.buy, entry, stop, target, stoch, last,
          divergence, 'Reversal oversold + pin bar/engulfing');
    }

    if (overboughtContext && bearReversal && cur.high > pcandle.high) {
      final entry = cur.close;
      final stop = cur.high * (1 + 0.002);
      final risk = stop - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = entry - 2.5 * risk;
      final divergence = _bearDivergence(candles, rsi);
      return _build(TradeDirection.sell, entry, stop, target, stoch, last,
          divergence, 'Reversal overbought + pin bar/engulfing');
    }

    return StrategyResult.none(id, name, note: 'Belum ada setup ekstrem');
  }

  bool _bullDivergence(List<Candle> c, List<double> rsi) {
    final lows = Indicators.swingLows(c, left: 2, right: 2);
    if (lows.length < 2) return false;
    final i1 = lows[lows.length - 2], i2 = lows[lows.length - 1];
    if (rsi[i1].isNaN || rsi[i2].isNaN) return false;
    return c[i2].low < c[i1].low && rsi[i2] > rsi[i1];
  }

  bool _bearDivergence(List<Candle> c, List<double> rsi) {
    final highs = Indicators.swingHighs(c, left: 2, right: 2);
    if (highs.length < 2) return false;
    final i1 = highs[highs.length - 2], i2 = highs[highs.length - 1];
    if (rsi[i1].isNaN || rsi[i2].isNaN) return false;
    return c[i2].high > c[i1].high && rsi[i2] < rsi[i1];
  }

  StrategyResult _build(
    String dir,
    double entry,
    double stop,
    double target,
    StochasticResult stoch,
    int last,
    bool divergence,
    String note,
  ) {
    double conf = 55;
    if (divergence) conf += 18; // divergensi menyertai -> +
    // Ekstremitas Stochastic menambah keyakinan.
    final k = stoch.k[last];
    final extreme = dir == TradeDirection.buy ? (20 - k) : (k - 80);
    conf += (extreme.clamp(0, 20)).toDouble();
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
        '%K': stoch.k[last].toStringAsFixed(1),
        '%D': stoch.d[last].toStringAsFixed(1),
        'Divergensi': divergence ? 'Ya' : 'Tidak',
      },
      note: note,
    );
  }
}
