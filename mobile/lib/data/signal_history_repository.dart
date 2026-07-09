import '../models/candle.dart';
import '../models/signal.dart';
import 'hive_cache.dart';

/// Statistik akurasi satu strategi.
class StrategyAccuracy {
  final int wins;
  final int losses;
  const StrategyAccuracy(this.wins, this.losses);

  int get total => wins + losses;

  /// Akurasi dasar 0..1. Default 0,5 saat belum ada data (prior netral).
  double get rate => total == 0 ? 0.5 : wins / total;
}

/// Menyimpan riwayat sinyal, mengevaluasi hasil (TP/SL), dan melacak akurasi
/// historis per strategi untuk pembobotan keyakinan.
class SignalHistoryRepository {
  final _box = HiveCache.signals();
  final _acc = HiveCache.accuracy();

  /// Semua sinyal, terbaru dulu.
  List<Signal> all() {
    final list = _box.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  List<Signal> pending() =>
      all().where((s) => s.outcome == SignalOutcome.pending).toList();

  /// Simpan sinyal baru bila belum ada untuk (simbol, candle) tsb.
  Future<void> add(Signal s) async {
    if (_box.containsKey(s.key)) return;
    await _box.put(s.key, s);
  }

  /// Akurasi dasar strategi (0..1) untuk pembobotan.
  double baseAccuracy(String strategyId) {
    final data = _acc.get(strategyId);
    if (data is Map) {
      final wins = (data['wins'] as num?)?.toInt() ?? 0;
      final losses = (data['losses'] as num?)?.toInt() ?? 0;
      return StrategyAccuracy(wins, losses).rate;
    }
    return 0.5;
  }

  StrategyAccuracy accuracyOf(String strategyId) {
    final data = _acc.get(strategyId);
    if (data is Map) {
      return StrategyAccuracy(
        (data['wins'] as num?)?.toInt() ?? 0,
        (data['losses'] as num?)?.toInt() ?? 0,
      );
    }
    return const StrategyAccuracy(0, 0);
  }

  Future<void> _recordOutcome(List<String> strategyIds, bool win) async {
    for (final id in strategyIds) {
      final cur = accuracyOf(id);
      await _acc.put(id, {
        'wins': cur.wins + (win ? 1 : 0),
        'losses': cur.losses + (win ? 0 : 1),
      });
    }
  }

  /// Evaluasi ulang sinyal pending terhadap candle baru per simbol.
  /// Sebuah sinyal dinyatakan TP/SL bila harga high/low candle setelah entry
  /// menyentuh level. Mengembalikan daftar sinyal yang baru terselesaikan.
  Future<List<Signal>> resolvePending(
    String symbol,
    List<Candle> closedCandles,
  ) async {
    final resolved = <Signal>[];
    for (final s in pending()) {
      if (s.symbol != symbol || !s.isActionable) continue;
      // Periksa candle yang tertutup SETELAH timestamp sinyal.
      for (final c in closedCandles) {
        if (c.openTime <= s.timestamp) continue;
        String? outcome;
        if (s.isBuy) {
          final hitSl = c.low <= s.stopLoss;
          final hitTp = c.high >= s.takeProfit;
          // Konservatif: bila keduanya tersentuh dalam satu candle, anggap SL.
          if (hitSl) {
            outcome = SignalOutcome.slHit;
          } else if (hitTp) {
            outcome = SignalOutcome.tpHit;
          }
        } else {
          final hitSl = c.high >= s.stopLoss;
          final hitTp = c.low <= s.takeProfit;
          if (hitSl) {
            outcome = SignalOutcome.slHit;
          } else if (hitTp) {
            outcome = SignalOutcome.tpHit;
          }
        }
        if (outcome != null) {
          final updated =
              s.copyWith(outcome: outcome, resolvedAt: c.closeTime);
          await _box.put(updated.key, updated);
          await _recordOutcome(
            s.triggeredStrategies,
            outcome == SignalOutcome.tpHit,
          );
          resolved.add(updated);
          break;
        }
      }
    }
    return resolved;
  }

  /// Statistik agregat untuk halaman Riwayat.
  HistoryStats stats() {
    final list = all();
    int tp = 0, sl = 0, pending = 0;
    for (final s in list) {
      switch (s.outcome) {
        case SignalOutcome.tpHit:
          tp++;
          break;
        case SignalOutcome.slHit:
          sl++;
          break;
        default:
          pending++;
      }
    }
    return HistoryStats(total: list.length, tp: tp, sl: sl, pending: pending);
  }

  Future<void> clear() async => _box.clear();
}

class HistoryStats {
  final int total;
  final int tp;
  final int sl;
  final int pending;
  const HistoryStats({
    required this.total,
    required this.tp,
    required this.sl,
    required this.pending,
  });

  double get winRate {
    final resolved = tp + sl;
    return resolved == 0 ? 0 : tp / resolved * 100;
  }
}
