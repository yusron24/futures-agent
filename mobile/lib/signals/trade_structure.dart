import '../config/app_config.dart';
import '../indicators/indicators.dart';
import '../models/candle.dart';

/// Tingkat temuan struktur (naik = makin serius).
enum StructureSeverity { ok, info, warn, violation }

class StructureFinding {
  final StructureSeverity severity;
  final String message;
  const StructureFinding(this.severity, this.message);
}

/// Laporan validasi struktur TP/SL. Bersifat KONTEKS: hanya `violation` (jarak SL
/// tak wajar) yang memicu penalti confidence kecil di engine; sisanya murni
/// informatif untuk penjelasan sinyal.
class StructureReport {
  final List<StructureFinding> findings;
  const StructureReport(this.findings);

  bool get hasViolation =>
      findings.any((f) => f.severity == StructureSeverity.violation);
  bool get hasWarn => findings
      .any((f) => f.severity.index >= StructureSeverity.warn.index);

  static const StructureReport empty = StructureReport([]);
}

/// Memvalidasi apakah TP/SL sebuah sinyal masuk akal terhadap struktur pasar
/// (level kunci support/resistance) dan jarak risiko. TIDAK mengubah RR/arah/
/// TP/SL — hanya menghasilkan temuan.
class TradeStructureValidator {
  TradeStructureValidator._();

  static StructureReport validate({
    required bool isBuy,
    required double entry,
    required double stop,
    required double takeProfit,
    required List<Candle> candles,
    double? minRiskPct,
    double? maxRiskPct,
    int? lookback,
  }) {
    final findings = <StructureFinding>[];
    if (entry <= 0) return StructureReport.empty;
    final minR = minRiskPct ?? AppConfig.structMinRiskPct;
    final maxR = maxRiskPct ?? AppConfig.structMaxRiskPct;
    final riskPct = (entry - stop).abs() / entry;
    final riskLabel = '${(riskPct * 100).toStringAsFixed(2)}%';

    // 1) Jarak SL wajar — SATU-SATUNYA yang memicu penalti (violation).
    if (riskPct < minR) {
      findings.add(StructureFinding(StructureSeverity.violation,
          'SL terlalu ketat ($riskLabel dari entry) — rawan ter-stop noise'));
    } else if (riskPct > maxR) {
      findings.add(StructureFinding(StructureSeverity.violation,
          'SL terlalu lebar ($riskLabel dari entry) — risiko per trade besar'));
    } else {
      findings.add(StructureFinding(
          StructureSeverity.ok, 'Jarak SL wajar ($riskLabel dari entry)'));
    }

    // Konteks struktur (informatif; tidak memicu penalti).
    final levels = Indicators.keyHorizontalLevels(candles,
        lookback: lookback ?? AppConfig.structKeyLevelLookback);
    if (levels.isNotEmpty) {
      // 2) SL terlindung level kunci?
      if (isBuy) {
        final support = levels.where((l) => l > stop && l < entry).toList();
        findings.add(support.isNotEmpty
            ? StructureFinding(StructureSeverity.info,
                'SL di bawah support ${support.last.toStringAsFixed(4)} (terlindung)')
            : const StructureFinding(StructureSeverity.warn,
                'SL tidak berada di bawah level kunci (mengambang)'));
      } else {
        final res = levels.where((l) => l < stop && l > entry).toList();
        findings.add(res.isNotEmpty
            ? StructureFinding(StructureSeverity.info,
                'SL di atas resistance ${res.first.toStringAsFixed(4)} (terlindung)')
            : const StructureFinding(StructureSeverity.warn,
                'SL tidak berada di atas level kunci (mengambang)'));
      }

      // 3) TP menembus level kunci lawan?
      final blockers = isBuy
          ? levels.where((l) => l > entry && l < takeProfit).toList()
          : levels.where((l) => l < entry && l > takeProfit).toList();
      findings.add(blockers.isEmpty
          ? const StructureFinding(
              StructureSeverity.ok, 'Tak ada level kunci menghalangi TP')
          : StructureFinding(StructureSeverity.warn,
              'TP menembus ${blockers.length} level kunci (agresif)'));
    }

    return StructureReport(findings);
  }
}
