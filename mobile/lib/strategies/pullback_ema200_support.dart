import '../indicators/indicators.dart';
import '../indicators/vwap.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 2 — Pullback ke EMA 200 + konfirmasi (swing 4 jam).
///
/// - Uptrend: harga > EMA200 dengan slope EMA200 positif.
/// - Pullback: harga ≤1% di atas EMA200.
/// - Konfirmasi: bullish engulfing ATAU morning star pada candle terakhir.
/// - SL: 1×ATR(14) di bawah low konfirmasi; TP = 2,5×SL.
/// - Batal bila TP di bawah swing high terakhir.
/// - Filter: RSI(14) > 40. (Downtrend = kebalikannya.)
class PullbackEma200Support extends Strategy {
  @override
  String get id => 'pullback_ema200_support';
  @override
  String get name => 'Pullback EMA200 + Konfirmasi';
  @override
  String get description =>
      'Pullback ke EMA200 searah tren dgn konfirmasi engulfing/star. '
      'RR tetap 1:2,5.';
  @override
  int get minCandles => 230;

  static const int emaPeriod = 200;
  static const int atrPeriod = 14;
  static const int rsiPeriod = 14;
  static const double pullbackTol = 0.01; // 1%
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final ema = Indicators.ema(closes, emaPeriod);
    final atr = Indicators.atr(candles, atrPeriod);
    final rsi = Indicators.rsi(closes, rsiPeriod);

    final last = candles.length - 1;
    final cur = candles[last];
    final prev = candles[last - 1];
    final entry = cur.close;
    final emaNow = ema[last];
    final emaPrev = ema[last - 5];
    if (emaNow.isNaN || emaPrev.isNaN || atr[last].isNaN || rsi[last].isNaN) {
      return StrategyResult.none(id, name);
    }
    final slope = (emaNow - emaPrev) / emaPrev;

    final uptrend = entry > emaNow && slope > 0.0003;
    final downtrend = entry < emaNow && slope < -0.0003;

    if (uptrend) {
      final dist = (entry - emaNow) / emaNow;
      if (dist > pullbackTol) {
        return StrategyResult.none(id, name, note: 'Belum pullback ke EMA200');
      }
      if (rsi[last] <= 40) {
        return StrategyResult.none(id, name, note: 'RSI ≤40 (momentum lemah)');
      }
      final confirm = Indicators.isBullishEngulfing(prev, cur) ||
          (last >= 2 &&
              Indicators.isMorningStar(candles[last - 2], prev, cur));
      if (!confirm) {
        return StrategyResult.none(id, name,
            note: 'Tanpa konfirmasi bullish');
      }
      final sl = cur.low - atr[last];
      final risk = entry - sl;
      if (risk <= 0) return StrategyResult.none(id, name);
      final tp = entry + rr * risk;
      final highs = Indicators.swingHighs(candles, left: 2, right: 2);
      if (highs.isNotEmpty) {
        final lastSwingHigh = candles[highs.last].high;
        if (tp < lastSwingHigh) {
          return StrategyResult.none(id, name,
              note: 'TP di bawah swing high terakhir');
        }
      }
      // Konfluens VWAP: JANGAN BUY bila harga di bawah VWAP (walau di atas EMA200).
      final vwap = VwapConfig.enabledForSignals
          ? Vwap.confluenceOf(candles, TradeDirection.buy, entry)
          : null;
      if (vwap != null && vwap.available && !vwap.aligned) {
        return StrategyResult.none(id, name,
            note: 'Harga di bawah VWAP — filter dibatalkan');
      }
      var conf = _confidence(rsi[last], slope.abs());
      if (vwap != null) {
        conf = vwap.adjust(conf, bonus: 6, penalty: 20, overPenalty: 8);
      }
      final ind = <String, String>{
        'EMA200': emaNow.toStringAsFixed(4),
        'Jarak ke EMA': '${(dist * 100).toStringAsFixed(2)}%',
        'RSI(14)': rsi[last].toStringAsFixed(1),
        'ATR(14)': atr[last].toStringAsFixed(4),
        'RR': '1:2,5',
      };
      if (vwap != null && vwap.available) {
        ind['VWAP'] = vwap.vwapValue.toStringAsFixed(4);
      }
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.buy,
        confidence: conf,
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: ind,
        note: 'Pullback bullish ke EMA200 + konfirmasi + VWAP',
      );
    }

    if (downtrend) {
      final dist = (emaNow - entry) / emaNow;
      if (dist > pullbackTol) {
        return StrategyResult.none(id, name, note: 'Belum pullback ke EMA200');
      }
      if (rsi[last] >= 60) {
        return StrategyResult.none(id, name, note: 'RSI ≥60 (momentum lemah)');
      }
      final confirm = Indicators.isBearishEngulfing(prev, cur) ||
          (last >= 2 &&
              Indicators.isEveningStar(candles[last - 2], prev, cur));
      if (!confirm) {
        return StrategyResult.none(id, name,
            note: 'Tanpa konfirmasi bearish');
      }
      final sl = cur.high + atr[last];
      final risk = sl - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final tp = entry - rr * risk;
      final lows = Indicators.swingLows(candles, left: 2, right: 2);
      if (lows.isNotEmpty) {
        final lastSwingLow = candles[lows.last].low;
        if (tp > lastSwingLow) {
          return StrategyResult.none(id, name,
              note: 'TP di atas swing low terakhir');
        }
      }
      // Konfluens VWAP: JANGAN SELL bila harga di atas VWAP (walau di bawah EMA200).
      final vwap = VwapConfig.enabledForSignals
          ? Vwap.confluenceOf(candles, TradeDirection.sell, entry)
          : null;
      if (vwap != null && vwap.available && !vwap.aligned) {
        return StrategyResult.none(id, name,
            note: 'Harga di atas VWAP — filter dibatalkan');
      }
      var conf = _confidence(100 - rsi[last], slope.abs());
      if (vwap != null) {
        conf = vwap.adjust(conf, bonus: 6, penalty: 20, overPenalty: 8);
      }
      final ind = <String, String>{
        'EMA200': emaNow.toStringAsFixed(4),
        'Jarak ke EMA': '${(dist * 100).toStringAsFixed(2)}%',
        'RSI(14)': rsi[last].toStringAsFixed(1),
        'ATR(14)': atr[last].toStringAsFixed(4),
        'RR': '1:2,5',
      };
      if (vwap != null && vwap.available) {
        ind['VWAP'] = vwap.vwapValue.toStringAsFixed(4);
      }
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.sell,
        confidence: conf,
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: ind,
        note: 'Pullback bearish ke EMA200 + konfirmasi + VWAP',
      );
    }

    return StrategyResult.none(id, name, note: 'Tidak ada tren jelas di EMA200');
  }

  double _confidence(double rsiStrength, double slopeStrength) {
    double c = 55;
    c += ((rsiStrength - 40) * 0.4).clamp(0, 20);
    c += (slopeStrength * 1500).clamp(0, 15);
    return c.clamp(0, 100);
  }
}
