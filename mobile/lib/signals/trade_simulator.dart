import '../models/candle.dart';
import '../models/signal.dart';

/// Hasil simulasi satu trade terhadap candle ke depan.
class SimResult {
  /// [SignalOutcome.tpHit] / [SignalOutcome.slHit], atau null bila belum tercapai.
  final String? outcome;

  /// Waktu (closeTime) candle penyelesaian, 0 bila belum.
  final int resolvedAt;

  /// Indeks candle penyelesaian pada list input, -1 bila belum.
  final int index;

  const SimResult(this.outcome, this.resolvedAt, this.index);

  static const SimResult pending = SimResult(null, 0, -1);
}

/// Simulator sentuh TP/SL — **satu sumber kebenaran** yang dipakai baik oleh
/// evaluasi live (`SignalHistoryRepository.resolvePending`) maupun backtest.
///
/// Aturan (identik untuk keduanya): periksa candle yang tertutup SETELAH
/// [afterTs]; sebuah trade dinyatakan TP/SL saat high/low candle menyentuh level.
/// **Konservatif**: bila SL dan TP tersentuh dalam candle yang SAMA → dianggap
/// SL (skenario terburuk, karena urutan intrabar tak diketahui dari klines).
SimResult simulateTradeOutcome({
  required bool isBuy,
  required double stopLoss,
  required double takeProfit,
  required int afterTs,
  required List<Candle> candles,
}) {
  for (int i = 0; i < candles.length; i++) {
    final c = candles[i];
    if (c.openTime <= afterTs) continue;
    String? outcome;
    if (isBuy) {
      final hitSl = c.low <= stopLoss;
      final hitTp = c.high >= takeProfit;
      if (hitSl) {
        outcome = SignalOutcome.slHit;
      } else if (hitTp) {
        outcome = SignalOutcome.tpHit;
      }
    } else {
      final hitSl = c.high >= stopLoss;
      final hitTp = c.low <= takeProfit;
      if (hitSl) {
        outcome = SignalOutcome.slHit;
      } else if (hitTp) {
        outcome = SignalOutcome.tpHit;
      }
    }
    if (outcome != null) return SimResult(outcome, c.closeTime, i);
  }
  return SimResult.pending;
}
