import '../models/candle.dart';

/// Tingkat keparahan masalah mutu data.
enum DqSeverity { ok, warn, block }

/// Hasil penilaian gerbang mutu data untuk satu simbol.
class DataQuality {
  final DqSeverity severity;
  final List<String> issues;
  const DataQuality(this.severity, this.issues);

  bool get ok => severity != DqSeverity.block;
  bool get hasIssues => issues.isNotEmpty;
  String get summary => issues.join('; ');

  static const DataQuality clean = DataQuality(DqSeverity.ok, []);
}

/// Gerbang mutu data: dijalankan SEBELUM strategi agar "input jelek" tidak
/// menghasilkan sinyal palsu (candle bolong/duplikat, data stale, volume
/// anomali, harga flat/illiquid).
///
/// Hanya bergantung pada candle + interval + waktu sekarang → murni & mudah
/// diuji. (Spread bid/ask tidak tersedia dari klines; didekati via range.)
class DataQualityGate {
  DataQualityGate._();

  static DataQuality assess(
    List<Candle> candles, {
    required int intervalMs,
    required int nowMs,
    int minCandles = 50,
    int staleFactor = 3,
    int volumeWindow = 20,
  }) {
    final issues = <String>[];
    var sev = DqSeverity.ok;
    void raise(DqSeverity s, String msg) {
      issues.add(msg);
      if (s.index > sev.index) sev = s;
    }

    if (candles.length < minCandles) {
      return DataQuality(
          DqSeverity.block, ['Data kurang (${candles.length}/$minCandles)']);
    }
    if (intervalMs <= 0) return DataQuality.clean;

    // Duplikat & gap berdasarkan jarak openTime yang seharusnya == intervalMs.
    int duplicates = 0, missing = 0, misaligned = 0;
    for (int i = 1; i < candles.length; i++) {
      final d = candles[i].openTime - candles[i - 1].openTime;
      if (d <= 0) {
        duplicates++;
      } else if (d != intervalMs) {
        if (d % intervalMs == 0) {
          missing += (d ~/ intervalMs) - 1;
        } else {
          misaligned++;
        }
      }
    }
    if (duplicates > 0) raise(DqSeverity.block, 'Candle duplikat ($duplicates)');
    if (misaligned > 0) {
      raise(DqSeverity.block, 'Candle tidak selaras interval ($misaligned)');
    }
    if (missing > 0) {
      // Sedikit gap → warn; banyak → block.
      if (missing > candles.length * 0.02) {
        raise(DqSeverity.block, 'Banyak candle bolong ($missing)');
      } else {
        raise(DqSeverity.warn, 'Ada candle bolong ($missing)');
      }
    }

    // Stale: candle terakhir tertutup terlalu lama (feed telat / simbol nonaktif).
    final age = nowMs - candles.last.openTime;
    if (age > staleFactor * intervalMs) {
      raise(DqSeverity.block,
          'Data stale (~${(age / intervalMs).floor()} candle tertinggal)');
    }

    // Volume anomali: run volume nol beruntun di jendela terakhir.
    int zeroRun = 0, maxZeroRun = 0;
    final startV = candles.length - volumeWindow;
    for (int i = startV < 0 ? 0 : startV; i < candles.length; i++) {
      if (candles[i].volume <= 0) {
        zeroRun++;
        if (zeroRun > maxZeroRun) maxZeroRun = zeroRun;
      } else {
        zeroRun = 0;
      }
    }
    if (maxZeroRun >= 3) {
      raise(DqSeverity.warn, 'Volume nol beruntun ($maxZeroRun)');
    }

    // Flatline/illiquid: beberapa candle terakhir nyaris tanpa range.
    bool flat = candles.length >= 3;
    for (int i = candles.length - 3; i < candles.length; i++) {
      if (i < 0) {
        flat = false;
        break;
      }
      final c = candles[i];
      if ((c.high - c.low) > c.close.abs() * 1e-6) {
        flat = false;
        break;
      }
    }
    if (flat) raise(DqSeverity.warn, 'Harga flat/illiquid');

    return DataQuality(sev, issues);
  }
}
