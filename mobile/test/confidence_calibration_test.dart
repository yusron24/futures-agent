import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/signals/confidence_calibration.dart';
import 'package:scalp_signals/strategies/strategy.dart';

void main() {
  group('ConfidenceCalibration', () {
    test('shrunkAccuracy: sample kecil mendekati prior, besar mendekati nyata',
        () {
      final small = ConfidenceCalibration.shrunkAccuracy(1, 0); // 1 menang
      expect(small, greaterThan(0.5));
      expect(small, lessThan(0.66)); // masih ditarik ke 0,5

      final big = ConfidenceCalibration.shrunkAccuracy(40, 10); // 80% dari 50
      expect(big, greaterThan(0.7)); // mendekati rasio nyata
      expect(big, lessThan(0.8));
    });

    test('sampleWeight naik monoton dengan jumlah sample', () {
      expect(ConfidenceCalibration.sampleWeight(0), 0);
      expect(ConfidenceCalibration.sampleWeight(2),
          lessThan(ConfidenceCalibration.sampleWeight(20)));
    });

    test('tierWeight: core > secondary > experimental', () {
      final c = ConfidenceCalibration.tierWeight(StrategyTier.core);
      final s = ConfidenceCalibration.tierWeight(StrategyTier.secondary);
      final e = ConfidenceCalibration.tierWeight(StrategyTier.experimental);
      expect(c, greaterThan(s));
      expect(s, greaterThan(e));
    });

    test('familyEffectiveWeights: sefamily terdiskon, beda family penuh', () {
      final w = ConfidenceCalibration.familyEffectiveWeights([
        ('trend', 1.0),
        ('trend', 0.5), // sefamily → terdiskon
        ('breakout', 0.8), // family lain → penuh
      ], discount: 0.65);
      expect(w[0], closeTo(1.0, 1e-9)); // primary
      expect(w[1], closeTo(0.5 * 0.65, 1e-9)); // terdiskon
      expect(w[2], closeTo(0.8, 1e-9)); // penuh
    });

    test('calibrate: bukti lemah → ke baseline; bukti cukup → ≈confRaw (≥70)',
        () {
      // Bukti nol → tertarik penuh ke baseline 50.
      expect(ConfidenceCalibration.calibrate(80, 0, baseline: 50, target: 0.55),
          closeTo(50, 1e-9));
      // Bukti ≥ target → confidence ≈ confRaw (guardrail: setup bagus tetap ≥70).
      final good = ConfidenceCalibration.calibrate(78, 0.55,
          baseline: 50, target: 0.55);
      expect(good, closeTo(78, 1e-9));
      expect(good, greaterThanOrEqualTo(70));
      // Bukti setengah target → di tengah.
      final mid = ConfidenceCalibration.calibrate(80, 0.275,
          baseline: 50, target: 0.55);
      expect(mid, closeTo(65, 1e-6));
    });
  });
}
