import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 1 — Breakout Level Kunci + Volume (swing 4 jam).
///
/// - Level horizontal "kunci" dari 100 candle terakhir (≥3 sentuhan).
/// - BUY: candle tertutup di ATAS resistance dengan volume ≥1,5× rata-rata 20.
///   SELL: candle tertutup di BAWAH support dengan volume ≥1,5× rata-rata 20.
/// - SL: 0,5% di bawah level atau low breakout (paling aman), TP = 2,5×SL.
/// - Batal bila TP menembus resistance/support historis berikutnya.
/// - Valid hanya bila jarak SL ≤3% dari entry.
class BreakoutKeyLevelVolume extends Strategy {
  @override
  String get id => 'breakout_key_level_volume';
  @override
  String get name => 'Breakout Level Kunci + Volume';
  @override
  String get description =>
      'Breakout level horizontal kunci (≥3 sentuhan) dgn konfirmasi volume '
      '≥1,5× rata-rata. RR tetap 1:2,5.';
  @override
  int get minCandles => 140;

  static const int lookback = 100;
  static const double levelTol = 0.005; // 0,5%
  static const int minTouches = 3;
  static const double volMult = 1.5;
  static const double maxSlPct = 0.03; // 3%
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final last = candles.length - 1;
    final cur = candles[last];
    final prev = candles[last - 1];
    final entry = cur.close;

    final volumes = Indicators.volumes(candles);
    double avg20 = 0;
    int cnt = 0;
    for (int i = last - 20; i < last; i++) {
      if (i >= 0) {
        avg20 += volumes[i];
        cnt++;
      }
    }
    if (cnt == 0) return StrategyResult.none(id, name);
    avg20 /= cnt;
    if (avg20 <= 0 || cur.volume < avg20 * volMult) {
      return StrategyResult.none(id, name, note: 'Volume breakout kurang');
    }
    final volRatio = cur.volume / avg20;

    final levels = Indicators.keyHorizontalLevels(
      candles,
      lookback: lookback,
      tol: levelTol,
      minTouches: minTouches,
    );
    if (levels.isEmpty) {
      return StrategyResult.none(id, name, note: 'Tidak ada level kunci');
    }

    // BUY: resistance terbesar yang baru ditembus ke atas oleh candle ini.
    double? brokenUp;
    for (final lv in levels) {
      if (cur.close > lv && prev.close <= lv * (1 + levelTol)) {
        if (brokenUp == null || lv > brokenUp) brokenUp = lv;
      }
    }
    // SELL: support terkecil yang baru ditembus ke bawah.
    double? brokenDown;
    for (final lv in levels) {
      if (cur.close < lv && prev.close >= lv * (1 - levelTol)) {
        if (brokenDown == null || lv < brokenDown) brokenDown = lv;
      }
    }

    if (brokenUp != null) {
      final level = brokenUp;
      final sl = math.min(level * (1 - levelTol), cur.low);
      final risk = entry - sl;
      if (risk <= 0) return StrategyResult.none(id, name);
      if (risk / entry > maxSlPct) {
        return StrategyResult.none(id, name, note: 'Jarak SL >3% dari entry');
      }
      final tp = entry + rr * risk;
      final nextRes = levels.where((l) => l > entry).fold<double?>(
          null, (a, b) => a == null ? b : math.min(a, b));
      if (nextRes != null && tp > nextRes) {
        return StrategyResult.none(id, name,
            note: 'TP melewati resistance berikutnya');
      }
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.buy,
        confidence: _confidence(volRatio),
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: {
          'Level': level.toStringAsFixed(4),
          'Volume': '${volRatio.toStringAsFixed(2)}× avg20',
          'RR': '1:2,5',
        },
        note: 'Breakout resistance kunci + lonjakan volume',
      );
    }

    if (brokenDown != null) {
      final level = brokenDown;
      final sl = math.max(level * (1 + levelTol), cur.high);
      final risk = sl - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      if (risk / entry > maxSlPct) {
        return StrategyResult.none(id, name, note: 'Jarak SL >3% dari entry');
      }
      final tp = entry - rr * risk;
      final nextSup = levels.where((l) => l < entry).fold<double?>(
          null, (a, b) => a == null ? b : math.max(a, b));
      if (nextSup != null && tp < nextSup) {
        return StrategyResult.none(id, name,
            note: 'TP melewati support berikutnya');
      }
      return StrategyResult(
        strategyId: id,
        strategyName: name,
        fired: true,
        direction: TradeDirection.sell,
        confidence: _confidence(volRatio),
        entry: entry,
        stopLoss: sl,
        takeProfit: tp,
        indicators: {
          'Level': level.toStringAsFixed(4),
          'Volume': '${volRatio.toStringAsFixed(2)}× avg20',
          'RR': '1:2,5',
        },
        note: 'Breakdown support kunci + lonjakan volume',
      );
    }

    return StrategyResult.none(id, name, note: 'Belum ada breakout level kunci');
  }

  double _confidence(double volRatio) {
    double c = 58;
    c += ((volRatio - volMult) * 20).clamp(0, 30);
    return c.clamp(0, 100);
  }
}
