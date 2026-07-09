import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 4 — Volume Profile Support/Resistance Flip.
///
/// - Bangun Volume Profile pada 200 candle 1h terakhir (POC + HVN).
/// - Temukan level yang dulu resistance lalu ditembus & kini diuji ulang.
/// - Konfirmasi: candle 1h menutup kembali di atas (support flip) / di bawah
///   (resistance flip) level tersebut.
/// - SL: ketat, tepat di bawah/atas level yang dibalik + buffer 0,5 ATR.
/// - TP: HVN/POC berikutnya — umumnya memberi R:R >= 1:3.
class VolumeProfileFlip extends Strategy {
  @override
  String get id => 'volume_profile_flip';
  @override
  String get name => 'Volume Profile S/R Flip';
  @override
  String get description =>
      'Retest level volume tinggi yang berubah peran (support/resistance flip).';
  @override
  int get minCandles => 210;

  static const int profileLen = 200;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final window = candles.sublist(candles.length - profileLen);
    final vp = Indicators.volumeProfile(window, bins: 60);
    final hvns = vp.highVolumeNodes(factor: 1.4);
    if (hvns.isEmpty) return StrategyResult.none(id, name);

    final atr = Indicators.atr(candles, 14);
    final last = candles.length - 1;
    if (atr[last].isNaN) return StrategyResult.none(id, name);
    final cur = candles[last];
    final prev = candles[last - 1];
    final tolerance = atr[last] * 0.6; // toleransi "menyentuh" level

    // Cari level HVN yang sedang diuji ulang oleh candle terakhir.
    double? level;
    double bestDist = double.infinity;
    for (final lv in hvns) {
      final d = (cur.low <= lv && cur.high >= lv)
          ? 0.0
          : math.min((cur.high - lv).abs(), (cur.low - lv).abs());
      if (d <= tolerance && d < bestDist) {
        bestDist = d;
        level = lv;
      }
    }
    if (level == null) {
      return StrategyResult.none(id, name, note: 'Tidak ada retest HVN');
    }

    // Support flip (dulu resistance, ditembus ke atas, kini retest & tahan):
    // harga sempat di bawah level lalu candle ditutup kembali di atas level.
    final flippedUp = prev.close < level && cur.close > level &&
        cur.low <= level; // menyentuh lalu tutup di atas
    // Resistance flip (dulu support, ditembus ke bawah, kini retest):
    final flippedDown = prev.close > level && cur.close < level &&
        cur.high >= level;

    if (flippedUp) {
      final entry = cur.close;
      final stop = level - 0.5 * atr[last];
      final risk = entry - stop;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = _nextNodeAbove(hvns, vp.poc, entry) ?? entry + 3 * risk;
      if (target <= entry) return StrategyResult.none(id, name);
      return _build(TradeDirection.buy, entry, stop, target, level, vp, last,
          'Support flip: retest HVN ditahan');
    }
    if (flippedDown) {
      final entry = cur.close;
      final stop = level + 0.5 * atr[last];
      final risk = stop - entry;
      if (risk <= 0) return StrategyResult.none(id, name);
      final target = _nextNodeBelow(hvns, vp.poc, entry) ?? entry - 3 * risk;
      if (target >= entry) return StrategyResult.none(id, name);
      return _build(TradeDirection.sell, entry, stop, target, level, vp, last,
          'Resistance flip: retest HVN ditolak');
    }

    return StrategyResult.none(id, name, note: 'Belum ada konfirmasi flip');
  }

  double? _nextNodeAbove(List<double> hvns, double poc, double from) {
    final cands = [poc, ...hvns].where((p) => p > from * 1.001).toList()..sort();
    return cands.isEmpty ? null : cands.first;
  }

  double? _nextNodeBelow(List<double> hvns, double poc, double from) {
    final cands = [poc, ...hvns].where((p) => p < from * 0.999).toList()..sort();
    return cands.isEmpty ? null : cands.last;
  }

  StrategyResult _build(
    String dir,
    double entry,
    double stop,
    double target,
    double level,
    VolumeProfile vp,
    int last,
    String note,
  ) {
    final risk = (entry - stop).abs();
    final reward = (target - entry).abs();
    final rr = risk == 0 ? 0 : reward / risk;
    double conf = 60;
    conf += ((rr - 2) * 8).clamp(0, 20); // R:R tinggi -> +
    conf += 8; // klaster volume dihormati
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
        'Level (HVN)': level.toStringAsFixed(4),
        'POC': vp.poc.toStringAsFixed(4),
        'R:R': rr.toStringAsFixed(2),
      },
      note: note,
    );
  }
}
