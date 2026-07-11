import '../models/candle.dart';
import '../models/strategy_result.dart';

/// Tingkatan strategi untuk ensemble terkalibrasi:
/// - [core]: paling stabil → **penentu arah (anchor)** & bobot utama.
/// - [secondary]: pendukung → menguatkan/melemahkan; jadi anchor hanya bila
///   tidak ada core.
/// - [experimental]: observasi → tidak boleh memicu sinyal sendiri; hanya
///   menambah keyakinan bila core/secondary searah.
enum StrategyTier { core, secondary, experimental }

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

  /// Tingkatan strategi (default secondary). Override di strategi masing-masing.
  StrategyTier get tier => StrategyTier.secondary;

  /// "Family" korelasi: strategi ber-family sama dianggap saling berkorelasi
  /// (bukti tumpang tindih) sehingga didiskon lembut di agregasi. Default unik
  /// per strategi (= [id]) → tidak saling diskon kecuali sengaja disamakan.
  String get family => id;

  /// Helper: harga entry = close candle terakhir (≈ open candle berikutnya).
  double entryPrice(List<Candle> c) => c.last.close;
}
