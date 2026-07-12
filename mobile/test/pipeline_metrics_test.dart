import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/services/pipeline_metrics.dart';
import 'package:scalp_signals/signals/signal_engine.dart';

void main() {
  group('PipelineMetrics', () {
    setUp(() => PipelineMetrics.instance.reset());

    test('record menaikkan count, total, actionable/held', () {
      final m = PipelineMetrics.instance;
      m.record(EvalReason.actionable);
      m.record(EvalReason.noSetup);
      m.record(EvalReason.dataBlocked);
      expect(m.total, 3);
      expect(m.count(EvalReason.actionable), 1);
      expect(m.actionableCount, 1);
      expect(m.heldCount, 2);
    });

    test('EvalReason.label & isHeld benar', () {
      expect(EvalReason.actionable.isHeld, false);
      expect(EvalReason.cooldown.isHeld, true);
      expect(EvalReason.regimeHold.label, isNotEmpty);
    });

    test('snapshot immutable', () {
      final m = PipelineMetrics.instance;
      m.record(EvalReason.actionable);
      final snap = m.snapshot();
      expect(snap.totalEvaluations, 1);
      expect(snap.actionable, 1);
      expect(() => snap.counts[EvalReason.noSetup] = 9,
          throwsUnsupportedError);
    });

    test('reset mengosongkan', () {
      final m = PipelineMetrics.instance;
      m.record(EvalReason.actionable);
      m.reset();
      expect(m.total, 0);
      expect(m.count(EvalReason.actionable), 0);
    });
  });
}
