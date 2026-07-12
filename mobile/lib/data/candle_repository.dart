import '../config/app_config.dart';
import '../models/candle.dart';
import 'hive_cache.dart';

/// Menyimpan & memelihara jendela bergulir candle per simbol **dan timeframe**,
/// dengan persistensi Hive agar pemuatan cepat dan tetap tersedia saat offline.
///
/// [interval] menentukan timeframe aktif; cache memori & Hive dipisah per
/// `simbol×interval` sehingga berganti timeframe TIDAK menghapus data timeframe
/// lain (kembali ke sana instan, tanpa fetch ulang).
class CandleRepository {
  final Map<String, List<Candle>> _memory = {};

  /// Timeframe aktif (mis. '1h'/'4h'/'1d'). Diatur oleh state saat init & ganti
  /// interval. Kunci cache mengikuti nilai ini.
  String interval = AppConfig.defaultInterval;

  String _key(String symbol) => '$symbol|$interval';

  /// Muat candle tersimpan dari cache (timeframe aktif) ke memori.
  Future<List<Candle>> loadCached(String symbol) async {
    final box = await HiveCache.candleBox(symbol, interval);
    final list = box.values.toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));
    _memory[_key(symbol)] = _trim(list);
    return _memory[_key(symbol)]!;
  }

  List<Candle> candles(String symbol) => _memory[_key(symbol)] ?? const [];

  /// Hanya candle yang sudah ditutup (untuk evaluasi strategi).
  List<Candle> closedCandles(String symbol) =>
      candles(symbol).where((c) => c.isClosed).toList();

  Candle? latest(String symbol) {
    final c = candles(symbol);
    return c.isEmpty ? null : c.last;
  }

  /// Kosongkan cache candle sebuah simbol pada timeframe aktif (memori + Hive).
  Future<void> clear(String symbol) async {
    _memory.remove(_key(symbol));
    final box = await HiveCache.candleBox(symbol, interval);
    await box.clear();
  }

  /// Ganti seluruh jendela (mis. setelah fetch REST awal) untuk timeframe aktif.
  Future<void> replaceAll(String symbol, List<Candle> fresh) async {
    final trimmed = _trim(List.of(fresh)
      ..sort((a, b) => a.openTime.compareTo(b.openTime)));
    _memory[_key(symbol)] = trimmed;
    final box = await HiveCache.candleBox(symbol, interval);
    await box.clear();
    // Key = openTime agar konsisten dengan applyUpdate (idempoten, tanpa duplikat).
    await box.putAll({for (final c in trimmed) c.openTime: c});
  }

  /// Terapkan update candle dari WebSocket. Mengembalikan candle yang BARU
  /// SAJA ditutup (transisi dari berjalan -> final) bila ada, jika tidak null.
  Future<Candle?> applyUpdate(String symbol, Candle incoming) async {
    final key = _key(symbol);
    final list = _memory.putIfAbsent(key, () => []);
    Candle? newlyClosed;

    if (list.isEmpty) {
      list.add(incoming);
    } else {
      final lastIdx = list.length - 1;
      final last = list[lastIdx];
      if (incoming.openTime == last.openTime) {
        // Update candle berjalan yang sama.
        final wasOpen = !last.isClosed;
        list[lastIdx] = incoming;
        if (wasOpen && incoming.isClosed) newlyClosed = incoming;
      } else if (incoming.openTime > last.openTime) {
        // Candle baru muncul. Jika candle sebelumnya belum ditandai closed,
        // pastikan ditutup (candle baru menandakan yang lama sudah final).
        if (!last.isClosed) {
          list[lastIdx] = last.copyWith(isClosed: true);
          newlyClosed = list[lastIdx];
        }
        list.add(incoming);
      } else {
        // Candle lama (out of order) — abaikan.
        return null;
      }
    }

    _memory[key] = _trim(list);
    await _persist(symbol, incoming);
    return newlyClosed;
  }

  Future<void> _persist(String symbol, Candle c) async {
    final box = await HiveCache.candleBox(symbol, interval);
    // Simpan dengan key = openTime agar idempoten.
    await box.put(c.openTime, c);
    // Pangkas box agar tidak tumbuh tak terbatas.
    if (box.length > AppConfig.candleWindow + 50) {
      final keys = box.keys.toList()..sort();
      final excess = box.length - AppConfig.candleWindow;
      await box.deleteAll(keys.take(excess));
    }
  }

  List<Candle> _trim(List<Candle> list) {
    if (list.length <= AppConfig.candleWindow) return list;
    return list.sublist(list.length - AppConfig.candleWindow);
  }
}
