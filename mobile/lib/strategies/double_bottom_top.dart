import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../indicators/vwap.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 4 — Double Bottom / Double Top (swing 4 jam).
///
/// - Double bottom: dua valley lokal berjarak ≥10 candle, selisih harga ≤1%,
///   volume formasi ke-2 lebih rendah. Entry saat close menembus neckline
///   (high tertinggi di antara dua valley). SL 0,5×ATR di bawah valley ke-2.
/// - Double top: kebalikannya (dua peak, neckline = low terendah antar peak).
/// - TP = 2,5×SL.
class DoubleBottomTop extends Strategy {
  @override
  String get id => 'double_bottom_top';
  @override
  String get name => 'Double Bottom / Top';
  @override
  String get description =>
      'Pola double bottom/top dgn breakout neckline & konfirmasi volume. '
      'RR tetap 1:2,5.';
  @override
  int get minCandles => 120;

  static const int minSeparation = 10;
  static const double priceTol = 0.01; // 1%
  static const int atrPeriod = 14;
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final atr = Indicators.atr(candles, atrPeriod);
    final last = candles.length - 1;
    final entry = candles[last].close;
    final prev = candles[last - 1];
    if (atr[last].isNaN) return StrategyResult.none(id, name);

    // --- Double bottom (BUY) ---
    final lows = Indicators.swingLows(candles, left: 3, right: 3);
    if (lows.length >= 2) {
      final i1 = lows[lows.length - 2];
      final i2 = lows[lows.length - 1];
      final v1 = candles[i1].low;
      final v2 = candles[i2].low;
      final farEnough = (i2 - i1) >= minSeparation;
      final similar = (v2 - v1).abs() / v1 <= priceTol;
      final volDrop = candles[i2].volume < candles[i1].volume;
      if (farEnough && similar && volDrop) {
        // Neckline = high tertinggi di antara dua valley.
        double neck = -double.infinity;
        for (int j = i1; j <= i2; j++) {
          neck = math.max(neck, candles[j].high);
        }
        final brokeUp = entry > neck && prev.close <= neck;
        if (brokeUp) {
          final sl = v2 - 0.5 * atr[last];
          final risk = entry - sl;
          if (risk > 0) {
            final tp = entry + rr * risk;
            final vwap = VwapConfig.enabledForSignals
                ? Vwap.confluenceOf(candles, TradeDirection.buy, entry)
                : null;
            var conf = _confidence((v2 - v1).abs() / v1);
            if (vwap != null) {
              conf = vwap.adjust(conf, bonus: 8, penalty: 15, overPenalty: 8);
            }
            final ind = <String, String>{
              'Neckline': neck.toStringAsFixed(4),
              'Valley': '${v1.toStringAsFixed(4)} / ${v2.toStringAsFixed(4)}',
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
              note: 'Double bottom + breakout neckline + VWAP',
            );
          }
        }
      }
    }

    // --- Double top (SELL) ---
    final highs = Indicators.swingHighs(candles, left: 3, right: 3);
    if (highs.length >= 2) {
      final i1 = highs[highs.length - 2];
      final i2 = highs[highs.length - 1];
      final p1 = candles[i1].high;
      final p2 = candles[i2].high;
      final farEnough = (i2 - i1) >= minSeparation;
      final similar = (p2 - p1).abs() / p1 <= priceTol;
      final volDrop = candles[i2].volume < candles[i1].volume;
      if (farEnough && similar && volDrop) {
        double neck = double.infinity;
        for (int j = i1; j <= i2; j++) {
          neck = math.min(neck, candles[j].low);
        }
        final brokeDown = entry < neck && prev.close >= neck;
        if (brokeDown) {
          final sl = p2 + 0.5 * atr[last];
          final risk = sl - entry;
          if (risk > 0) {
            final tp = entry - rr * risk;
            final vwap = VwapConfig.enabledForSignals
                ? Vwap.confluenceOf(candles, TradeDirection.sell, entry)
                : null;
            var conf = _confidence((p2 - p1).abs() / p1);
            if (vwap != null) {
              conf = vwap.adjust(conf, bonus: 8, penalty: 15, overPenalty: 8);
            }
            final ind = <String, String>{
              'Neckline': neck.toStringAsFixed(4),
              'Peak': '${p1.toStringAsFixed(4)} / ${p2.toStringAsFixed(4)}',
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
              note: 'Double top + breakdown neckline + VWAP',
            );
          }
        }
      }
    }

    return StrategyResult.none(id, name, note: 'Tanpa pola double valid');
  }

  double _confidence(double priceDiff) {
    // Semakin mirip kedua valley/peak, semakin tinggi keyakinan.
    double c = 60;
    c += ((priceTol - priceDiff) / priceTol * 25).clamp(0, 25);
    return c.clamp(0, 100);
  }
}
