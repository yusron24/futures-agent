import '../config/app_config.dart';
import '../strategies/strategy.dart';

/// Matematika kalibrasi confidence (murni & mudah diuji). Sumber tunggal agar
/// tiap lapisan punya peran jelas dan tidak menekan confidence dua kali.
class ConfidenceCalibration {
  ConfidenceCalibration._();

  /// Akurasi menyusut ke [prior] untuk sample kecil (Bayesian shrinkage).
  /// Hanya memengaruhi BOBOT arah, bukan evidence kalibrasi.
  static double shrunkAccuracy(
    double wins,
    double losses, {
    double prior = 0.5,
    double? k,
  }) {
    final kk = k ?? AppConfig.calibShrinkK;
    final total = wins + losses;
    if (total <= 0) return prior;
    return (wins + kk * prior) / (total + kk);
  }

  /// Keandalan estimasi 0..1 (naik monoton dengan jumlah sample).
  static double sampleWeight(double total, {double? k}) {
    final kk = k ?? AppConfig.calibShrinkK;
    if (total <= 0) return 0;
    return total / (total + kk);
  }

  /// Bobot tier: core > secondary > experimental.
  static double tierWeight(StrategyTier t) {
    switch (t) {
      case StrategyTier.core:
        return AppConfig.tierWeightCore;
      case StrategyTier.secondary:
        return AppConfig.tierWeightSecondary;
      case StrategyTier.experimental:
        return AppConfig.tierWeightExperimental;
    }
  }

  /// Diskon korelasi: dalam satu family, hanya bobot TERBESAR yang penuh;
  /// anggota family yang sama lainnya × [discount]. Mengembalikan bobot efektif
  /// per elemen (urutan sama dengan input).
  static List<double> familyEffectiveWeights(
    List<(String, double)> items, {
    double? discount,
  }) {
    final d = discount ?? AppConfig.familyDiscount;
    // Index "primary" (bobot terbesar) per family.
    final primaryIdx = <String, int>{};
    for (int i = 0; i < items.length; i++) {
      final f = items[i].$1;
      final cur = primaryIdx[f];
      if (cur == null || items[i].$2 > items[cur].$2) primaryIdx[f] = i;
    }
    return [
      for (int i = 0; i < items.length; i++)
        primaryIdx[items[i].$1] == i ? items[i].$2 : items[i].$2 * d,
    ];
  }

  /// Total bobot efektif setelah diskon family.
  static double familyEffectiveTotal(
    List<(String, double)> items, {
    double? discount,
  }) {
    final w = familyEffectiveWeights(items, discount: discount);
    return w.fold(0.0, (a, b) => a + b);
  }

  /// Kalibrasi confidence akhir: tarik ke [baseline] saat [evidence] < [target].
  /// Bukti dibangun dari kesepakatan STRUKTURAL (tier×conf), TANPA akurasi/sample,
  /// agar sample kecil tidak menekan confidence dua kali.
  static double calibrate(
    double confRaw,
    double evidence, {
    double? baseline,
    double? target,
  }) {
    final b = baseline ?? AppConfig.confBaseline;
    final t = target ?? AppConfig.evidenceTarget;
    final reliability = (t <= 0 ? 1.0 : evidence / t).clamp(0.0, 1.0);
    return b + (confRaw - b) * reliability;
  }
}
