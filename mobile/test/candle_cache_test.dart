import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:scalp_signals/data/candle_repository.dart';
import 'package:scalp_signals/models/candle.dart';

List<Candle> _mk(int n, double base) => List.generate(
      n,
      (i) => Candle(
        openTime: i * 100,
        open: base,
        high: base + 1,
        low: base - 1,
        close: base + i,
        volume: 1,
        closeTime: i * 100 + 1,
      ),
    );

void main() {
  group('CandleRepository cache per symbol×timeframe (Fase 6)', () {
    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('hive_candle_cache');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(CandleAdapter());
    });

    test('timeframe berbeda → cache terpisah, tidak saling menimpa', () async {
      final repo = CandleRepository();

      repo.interval = '4h';
      final a = _mk(5, 100);
      await repo.replaceAll('BTCUSDT', a);
      expect(repo.candles('BTCUSDT').length, 5);

      // Pindah ke 1h → cache 4h tak terlihat (key beda), belum dimuat.
      repo.interval = '1h';
      expect(repo.candles('BTCUSDT'), isEmpty);
      final b = _mk(3, 200);
      await repo.replaceAll('BTCUSDT', b);
      expect(repo.candles('BTCUSDT').length, 3);

      // Kembali ke 4h → data lama UTUH (tidak tertimpa oleh 1h).
      repo.interval = '4h';
      final loaded4h = await repo.loadCached('BTCUSDT');
      expect(loaded4h.length, 5);
      expect(loaded4h.last.close, a.last.close);

      // 1h juga tetap ada.
      repo.interval = '1h';
      final loaded1h = await repo.loadCached('BTCUSDT');
      expect(loaded1h.length, 3);
      expect(loaded1h.last.close, b.last.close);
    });
  });
}
