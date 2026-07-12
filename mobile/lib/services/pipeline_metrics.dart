import '../signals/signal_engine.dart';

/// Snapshot metrik pipeline (immutable) untuk UI Diagnostik.
class MetricsSnapshot {
  final int totalEvaluations;
  final int lastEvalMs;
  final Map<EvalReason, int> counts;
  const MetricsSnapshot({
    required this.totalEvaluations,
    required this.lastEvalMs,
    required this.counts,
  });

  int count(EvalReason r) => counts[r] ?? 0;
  int get actionable => count(EvalReason.actionable);
  int get held => totalEvaluations - actionable;
}

/// Penghitung metrik alur sinyal (Fase 5 — observability). Singleton ringan
/// (pola [SystemHealth]); dicatat oleh PEMANGGIL engine (state), bukan oleh
/// engine, agar engine tetap murni & deterministik.
class PipelineMetrics {
  PipelineMetrics._();
  static final PipelineMetrics instance = PipelineMetrics._();

  final Map<EvalReason, int> _counts = {};
  int _total = 0;
  int _lastMs = 0;

  /// Catat satu hasil evaluasi menurut alasan terstrukturnya.
  void record(EvalReason reason) {
    _counts[reason] = (_counts[reason] ?? 0) + 1;
    _total++;
    _lastMs = DateTime.now().millisecondsSinceEpoch;
  }

  int count(EvalReason reason) => _counts[reason] ?? 0;
  int get total => _total;
  int get actionableCount => count(EvalReason.actionable);
  int get heldCount => _total - actionableCount;

  MetricsSnapshot snapshot() => MetricsSnapshot(
        totalEvaluations: _total,
        lastEvalMs: _lastMs,
        counts: Map<EvalReason, int>.unmodifiable(_counts),
      );

  void reset() {
    _counts.clear();
    _total = 0;
    _lastMs = 0;
  }
}
