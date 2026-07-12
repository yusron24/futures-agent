/// Seam ringan yang dibutuhkan [SignalEngine] dari sumber statistik historis.
///
/// Hanya dua metode inilah yang dipakai engine dari repositori riwayat, sehingga
/// backtest dapat me-*replay* engine yang SAMA dengan implementasi in-memory
/// (yang berevolusi walk-forward) tanpa menyentuh Hive/penyimpanan live.
abstract class SignalStatsSource {
  /// Akurasi terkalibrasi (shrinkage sample kecil) 0..1 untuk pembobotan arah.
  double calibratedAccuracy(String strategyId);

  /// Apakah simbol sedang dalam cooldown pada waktu [nowMs].
  bool inCooldown(String symbol, int nowMs);
}
