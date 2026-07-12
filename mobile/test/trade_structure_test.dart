import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/signals/trade_structure.dart';

/// Gelombang segitiga 100↔110 (periode 8) → level kunci ~99,9 (support) &
/// ~110,1 (resistance), masing-masing disentuh banyak kali.
List<Candle> _triangle() {
  const seq = [100.0, 102.5, 105.0, 107.5, 110.0, 107.5, 105.0, 102.5];
  final out = <Candle>[];
  for (int i = 0; i < 64; i++) {
    final v = seq[i % 8];
    final o = i == 0 ? v : seq[(i - 1) % 8];
    out.add(Candle(
      openTime: i * 100,
      open: o,
      high: v + 0.1,
      low: v - 0.1,
      close: v,
      volume: 100,
      closeTime: i * 100 + 1,
    ));
  }
  return out;
}

void main() {
  group('TradeStructureValidator', () {
    test('SL terlalu ketat → violation', () {
      final r = TradeStructureValidator.validate(
        isBuy: true,
        entry: 100,
        stop: 99.9, // 0,1% < 0,3%
        takeProfit: 105,
        candles: const [],
      );
      expect(r.hasViolation, true);
    });

    test('SL terlalu lebar → violation', () {
      final r = TradeStructureValidator.validate(
        isBuy: true,
        entry: 100,
        stop: 80, // 20% > 15%
        takeProfit: 150,
        candles: const [],
      );
      expect(r.hasViolation, true);
    });

    test('jarak SL wajar → tanpa violation', () {
      final r = TradeStructureValidator.validate(
        isBuy: true,
        entry: 100,
        stop: 98, // 2%
        takeProfit: 105,
        candles: const [],
      );
      expect(r.hasViolation, false);
    });

    test('BUY: SL di bawah support & TP menembus resistance → warn, bukan violation',
        () {
      final r = TradeStructureValidator.validate(
        isBuy: true,
        entry: 105,
        stop: 99, // di bawah support ~99,9
        takeProfit: 120, // menembus resistance ~110,1
        candles: _triangle(),
      );
      expect(r.hasViolation, false); // risk% wajar
      expect(r.hasWarn, true); // TP menembus level kunci
      expect(r.findings.any((f) => f.message.contains('TP menembus')), true);
      expect(r.findings.any((f) => f.message.contains('terlindung')), true);
    });
  });
}
