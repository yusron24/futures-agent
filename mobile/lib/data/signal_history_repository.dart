import '../config/app_config.dart';
import '../models/candle.dart';
import '../models/signal.dart';
import '../signals/confidence_calibration.dart';
import 'hive_cache.dart';

/// Statistik akurasi satu strategi (berbobot-waktu; wins/losses bisa pecahan
/// karena decay).
class StrategyAccuracy {
  final double wins;
  final double losses;
  const StrategyAccuracy(this.wins, this.losses);

  double get total => wins + losses;

  /// Akurasi dasar 0..1. Default 0,5 saat belum ada data (prior netral).
  double get rate => total <= 0 ? 0.5 : wins / total;
}

/// Menyimpan riwayat sinyal, mengevaluasi hasil (TP/SL), dan melacak akurasi
/// historis per strategi untuk pembobotan keyakinan.
class SignalHistoryRepository {
  final _box = HiveCache.signals();
  final _acc = HiveCache.accuracy();
  final _cool = HiveCache.settings();

  // --- Cooldown per simbol (epoch ms sampai kapan sinyal ditahan) ---
  int cooldownUntil(String symbol) =>
      (_cool.get('cooldown_$symbol') as num?)?.toInt() ?? 0;

  bool inCooldown(String symbol, int nowMs) => nowMs < cooldownUntil(symbol);

  Future<void> setCooldown(String symbol, int untilMs) async =>
      _cool.put('cooldown_$symbol', untilMs);

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

  /// Akurasi dasar strategi (0..1) untuk pembobotan (rasio mentah).
  double baseAccuracy(String strategyId) => accuracyOf(strategyId).rate;

  /// Akurasi TERKALIBRASI (shrinkage sample kecil) — dipakai engine sebagai
  /// bobot arah agar strategi minim histori tidak overconfident.
  double calibratedAccuracy(String strategyId) {
    final a = accuracyOf(strategyId);
    return ConfidenceCalibration.shrunkAccuracy(a.wins, a.losses);
  }

  StrategyAccuracy accuracyOf(String strategyId) {
    final data = _acc.get(strategyId);
    if (data is Map) {
      return StrategyAccuracy(
        (data['wins'] as num?)?.toDouble() ?? 0,
        (data['losses'] as num?)?.toDouble() ?? 0,
      );
    }
    return const StrategyAccuracy(0, 0);
  }

  /// Perbarui akurasi dengan DECAY (bobot hasil lama diperkecil) sehingga
  /// performa terbaru lebih menentukan.
  Future<void> _recordOutcome(List<String> strategyIds, bool win) async {
    const decay = AppConfig.calibDecay;
    for (final id in strategyIds) {
      final cur = accuracyOf(id);
      await _acc.put(id, {
        'wins': cur.wins * decay + (win ? 1 : 0),
        'losses': cur.losses * decay + (win ? 0 : 1),
      });
    }
  }

  /// Evaluasi ulang sinyal pending terhadap candle baru per simbol.
  /// Sebuah sinyal dinyatakan TP/SL bila harga high/low candle setelah entry
  /// menyentuh level. Mengembalikan daftar sinyal yang baru terselesaikan.
  Future<List<Signal>> resolvePending(
    String symbol,
    List<Candle> closedCandles, {
    int cooldownMs = 0,
  }) async {
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
          // Laba/rugi dalam kelipatan-R: +riskReward saat TP, −1 saat SL.
          final pl = outcome == SignalOutcome.tpHit ? s.riskReward : -1.0;
          final updated = s.copyWith(
            outcome: outcome,
            resolvedAt: c.closeTime,
            profitLoss: pl,
          );
          await _box.put(updated.key, updated);
          await _recordOutcome(
            s.triggeredStrategies,
            outcome == SignalOutcome.tpHit,
          );
          // Pasang cooldown: lebih panjang setelah SL daripada TP.
          if (cooldownMs > 0) {
            final mult = outcome == SignalOutcome.slHit ? 1.0 : 0.5;
            await setCooldown(
                symbol, c.closeTime + (cooldownMs * mult).round());
          }
          resolved.add(updated);
          break;
        }
      }
    }
    return resolved;
  }

  /// Tandai sebuah sinyal sebagai diabaikan (tombol "Reset sinyal"). Sinyal
  /// tetap tersimpan namun dikecualikan dari statistik & tidak aktif lagi.
  Future<void> ignore(Signal s) async {
    final updated = s.copyWith(outcome: SignalOutcome.ignored, profitLoss: 0);
    await _box.put(updated.key, updated);
  }

  /// Statistik agregat untuk halaman Riwayat. Sinyal berstatus `ignored`
  /// dikecualikan; `pending` dihitung sebagai "running".
  HistoryStats stats() {
    final list = all();
    int total = 0, tp = 0, sl = 0, pending = 0;
    double totalProfit = 0, totalLoss = 0;
    for (final s in list) {
      if (s.outcome == SignalOutcome.ignored) continue;
      total++;
      switch (s.outcome) {
        case SignalOutcome.tpHit:
          tp++;
          totalProfit += s.profitLoss > 0 ? s.profitLoss : 0;
          break;
        case SignalOutcome.slHit:
          sl++;
          totalLoss += s.profitLoss < 0 ? -s.profitLoss : 0;
          break;
        default:
          pending++;
      }
    }
    return HistoryStats(
      total: total,
      tp: tp,
      sl: sl,
      pending: pending,
      totalProfit: totalProfit,
      totalLoss: totalLoss,
    );
  }

  Future<void> clear() async => _box.clear();
}

class HistoryStats {
  final int total;
  final int tp;
  final int sl;
  final int pending;
  final double totalProfit; // total laba (kelipatan-R)
  final double totalLoss; // total rugi absolut (kelipatan-R)
  const HistoryStats({
    required this.total,
    required this.tp,
    required this.sl,
    required this.pending,
    this.totalProfit = 0,
    this.totalLoss = 0,
  });

  double get winRate {
    final resolved = tp + sl;
    return resolved == 0 ? 0 : tp / resolved * 100;
  }

  /// Profit factor = total laba / total rugi. Null bila belum ada rugi
  /// (ditampilkan sebagai "∞"/"N/A" di UI).
  double? get profitFactor {
    if (totalLoss <= 0) return null;
    return totalProfit / totalLoss;
  }
}
