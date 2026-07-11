import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/signals/data_quality.dart';

const int _iv = 14400000; // 4 jam

Candle _c(int t, double price, double vol) => Candle(
      openTime: t,
      open: price,
      high: price * 1.001,
      low: price * 0.999,
      close: price,
      volume: vol,
      closeTime: t + 1,
    );

List<Candle> _series(int n, {double vol = 10}) =>
    [for (int i = 0; i < n; i++) _c(i * _iv, 100 + i.toDouble(), vol)];

// nowMs "segar": tepat satu interval setelah candle terakhir.
int _freshNow(List<Candle> c) => c.last.openTime + _iv;

void main() {
  group('DataQualityGate', () {
    test('seri bersih → ok', () {
      final c = _series(60);
      final dq =
          DataQualityGate.assess(c, intervalMs: _iv, nowMs: _freshNow(c));
      expect(dq.severity, DqSeverity.ok);
      expect(dq.ok, true);
    });

    test('data kurang → block', () {
      final c = _series(20);
      final dq =
          DataQualityGate.assess(c, intervalMs: _iv, nowMs: _freshNow(c));
      expect(dq.severity, DqSeverity.block);
      expect(dq.ok, false);
    });

    test('candle duplikat → block', () {
      final c = _series(60);
      // Sisipkan duplikat openTime.
      final dup = <Candle>[...c.sublist(0, 30), c[29], ...c.sublist(30)];
      final dq =
          DataQualityGate.assess(dup, intervalMs: _iv, nowMs: _freshNow(dup));
      expect(dq.severity, DqSeverity.block);
    });

    test('gap besar (banyak candle bolong) → block', () {
      // Buat lompatan 5×interval di tengah.
      final c = <Candle>[
        for (int i = 0; i < 30; i++) _c(i * _iv, 100 + i.toDouble(), 10),
        for (int i = 35; i < 65; i++) _c(i * _iv, 100 + i.toDouble(), 10),
      ];
      final dq =
          DataQualityGate.assess(c, intervalMs: _iv, nowMs: _freshNow(c));
      expect(dq.severity, DqSeverity.block);
    });

    test('gap kecil (1 candle bolong) → warn', () {
      final c = <Candle>[
        for (int i = 0; i < 40; i++) _c(i * _iv, 100 + i.toDouble(), 10),
        for (int i = 41; i < 61; i++) _c(i * _iv, 100 + i.toDouble(), 10),
      ];
      final dq =
          DataQualityGate.assess(c, intervalMs: _iv, nowMs: _freshNow(c));
      expect(dq.severity, DqSeverity.warn);
      expect(dq.ok, true);
    });

    test('data stale → block', () {
      final c = _series(60);
      final dq = DataQualityGate.assess(c,
          intervalMs: _iv, nowMs: c.last.openTime + 10 * _iv);
      expect(dq.severity, DqSeverity.block);
    });

    test('volume nol beruntun → warn', () {
      final c = <Candle>[
        for (int i = 0; i < 55; i++) _c(i * _iv, 100 + i.toDouble(), 10),
        for (int i = 55; i < 60; i++) _c(i * _iv, 100 + i.toDouble(), 0),
      ];
      final dq =
          DataQualityGate.assess(c, intervalMs: _iv, nowMs: _freshNow(c));
      expect(dq.severity, DqSeverity.warn);
      expect(dq.ok, true);
    });
  });
}
