import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 2 — Bollinger Bands Squeeze Breakout.
///
/// - BB(20,2). Squeeze bila bandwidth berada di 10% terendah dari 100 candle.
/// - Candle 1h menutup di luar pita, volume > 1,5× rata-rata volume 20 periode.
/// - SL: pita tengah (SMA20) saat squeeze.
/// - TP: jarak (pita tengah -> level breakout) × 2,5 (asimetris).
class BollingerSqueezeBreakout extends Strategy {
  @override
  String get id => 'bb_squeeze_breakout';
  @override
  String get name => 'Bollinger Squeeze Breakout';
  @override
  String get description =>
      'Breakout bervolume tinggi keluar dari konsolidasi (BB squeeze).';
  @override
  int get minCandles => 120;

  static const int bbPeriod = 20;
  static const double bbMult = 2.0;
  static const int lookback = 100;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final bb = Indicators.bollinger(closes, period: bbPeriod, mult: bbMult);
    final volSma = Indicators.sma(Indicators.volumes(candles), bbPeriod);

    final last = candles.length - 1;
    if (bb.bandwidth[last].isNaN || volSma[last].isNaN) {
      return StrategyResult.none(id, name);
    }

    // Squeeze: bandwidth candle SEBELUM breakout berada di persentil 10 bawah
    // atas 100 candle terakhir.
    final prev = last - 1;
    if (bb.bandwidth[prev].isNaN) return StrategyResult.none(id, name);
    final window = <double>[];
    for (int i = prev; i >= 0 && window.length < lookback; i--) {
      if (!bb.bandwidth[i].isNaN) window.add(bb.bandwidth[i]);
    }
    if (window.length < 30) return StrategyResult.none(id, name);
    final sorted = [...window]..sort();
    final p10 = sorted[(sorted.length * 0.10).floor()];
    final wasSqueezed = bb.bandwidth[prev] <= p10;
    if (!wasSqueezed) {
      return StrategyResult.none(id, name, note: 'Tidak ada squeeze');
    }

    final c = candles[last];
    final volOk = c.volume > 1.5 * volSma[last];
    if (!volOk) {
      return StrategyResult.none(id, name, note: 'Volume breakout kurang');
    }

    final mid = bb.middle[last];
    if (c.close > bb.upper[last]) {
      // Breakout ke atas.
      final entry = c.close;
      final stop = mid; // pita tengah
      final risk = entry - stop;
      if (risk <= 0) return StrategyResult.none(id, name);
      final distFromMid = c.close - mid;
      final target = mid + distFromMid * 2.5;
      return _build(
        TradeDirection.buy, entry, stop, target, bb, volSma, c, last,
        'Breakout bullish keluar squeeze',
      );
    } else if (c.close < bb.lower[last]) {
      // Breakout ke bawah.
      final entry = c.close;
      final stop = mid;
      final risk = stop - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final distFromMid = mid - c.close;
      final target = mid - distFromMid * 2.5;
      return _build(
        TradeDirection.sell, entry, stop, target, bb, volSma, c, last,
        'Breakout bearish keluar squeeze',
      );
    }
    return StrategyResult.none(id, name, note: 'Belum menembus pita');
  }

  StrategyResult _build(
    String dir,
    double entry,
    double stop,
    double target,
    BollingerResult bb,
    List<double> volSma,
    Candle c,
    int last,
    String note,
  ) {
    final volRatio = volSma[last] == 0 ? 0.0 : c.volume / volSma[last];
    double conf = 60;
    conf += ((volRatio - 1.5) * 20).clamp(0, 25); // volume makin besar -> +
    // Penutupan candle yang tegas (badan besar) menambah keyakinan.
    final range = c.high - c.low;
    if (range > 0) {
      final bodyRatio = (c.close - c.open).abs() / range;
      conf += (bodyRatio * 15).clamp(0, 15);
    }
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
        'BB Upper': bb.upper[last].toStringAsFixed(4),
        'BB Mid': bb.middle[last].toStringAsFixed(4),
        'BB Lower': bb.lower[last].toStringAsFixed(4),
        'Vol x avg': volRatio.toStringAsFixed(2),
      },
      note: note,
    );
  }
}
