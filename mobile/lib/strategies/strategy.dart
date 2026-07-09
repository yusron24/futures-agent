import '../models/candle.dart';
import '../models/strategy_result.dart';

/// Kontrak untuk setiap strategi scalping.
///
/// [evaluate] menerima daftar candle **yang sudah ditutup** (terurut menaik),
/// dengan elemen terakhir sebagai candle penutup terbaru. Entry sinyal adalah
/// pembukaan candle berikutnya, yang secara praktis setara dengan harga close
/// candle terakhir.
abstract class Strategy {
  /// ID stabil (dipakai untuk pelacakan akurasi & toggle pengaturan).
  String get id;

  /// Nama tampilan.
  String get name;

  /// Penjelasan singkat logika.
  String get description;

  /// Minimal jumlah candle agar strategi dapat dievaluasi.
  int get minCandles;

  StrategyResult evaluate(String symbol, List<Candle> candles);

  /// Helper: harga entry = close candle terakhir (≈ open candle berikutnya).
  double entryPrice(List<Candle> c) => c.last.close;
}
