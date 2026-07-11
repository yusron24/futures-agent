import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/indicators/vwap.dart';
import 'package:scalp_signals/models/candle.dart';

// Candle dengan typical price = close bila h=l=c (memudahkan verifikasi).
Candle _c(int t, double price, double v) => Candle(
      openTime: t,
      open: price,
      high: price,
      low: price,
      close: price,
      volume: v,
      closeTime: t + 1,
    );

void main() {
  group('VWAP', () {
    test('volume seragam → VWAP rolling = SMA typical price', () {
      final closes = [10.0, 11, 12, 13, 14, 15, 16, 17];
      final c = [for (int i = 0; i < closes.length; i++) _c(i * 3600000, closes[i], 10)];
      final r = Vwap.compute(c, mode: VwapMode.rolling, period: 5);
      // index4 = avg(10..14)=12 ; index7 = avg(13..17)=15
      expect(r.vwap[3].isNaN, true); // warmup
      expect(r.vwap[4], closeTo(12, 1e-9));
      expect(r.vwap[7], closeTo(15, 1e-9));
    });

    test('volume berat menarik VWAP ke candle tersebut', () {
      final c = [
        _c(0, 10, 1),
        _c(1, 10, 1),
        _c(2, 10, 1),
        _c(3, 10, 1),
        _c(4, 20, 100), // volume besar di harga 20
      ];
      final r = Vwap.compute(c, mode: VwapMode.rolling, period: 5);
      // Weighted jauh di atas rata-rata sederhana (12).
      expect(r.vwap[4], greaterThan(18));
      expect(r.vwap[4], lessThanOrEqualTo(20));
    });

    test('volume nol → fallback rata-rata (tanpa NaN/crash)', () {
      final closes = [10.0, 11, 12, 13, 14];
      final c = [for (int i = 0; i < closes.length; i++) _c(i * 3600000, closes[i], 0)];
      final r = Vwap.compute(c, mode: VwapMode.rolling, period: 5);
      expect(r.vwap[4].isNaN, false);
      expect(r.vwap[4], closeTo(12, 1e-9));
    });

    test('urutan band: upper3≥upper2≥upper1≥vwap≥lower1≥lower2≥lower3', () {
      final vals = [10.0, 12, 9, 14, 8, 15, 11, 13, 10, 16];
      final c = [for (int i = 0; i < vals.length; i++) _c(i * 3600000, vals[i], 5 + i.toDouble())];
      final r = Vwap.compute(c, mode: VwapMode.rolling, period: 5);
      final p = r.last!;
      expect(p.upper3, greaterThanOrEqualTo(p.upper2));
      expect(p.upper2, greaterThanOrEqualTo(p.upper1));
      expect(p.upper1, greaterThanOrEqualTo(p.vwap));
      expect(p.vwap, greaterThanOrEqualTo(p.lower1));
      expect(p.lower1, greaterThanOrEqualTo(p.lower2));
      expect(p.lower2, greaterThanOrEqualTo(p.lower3));
    });

    test('anchored harian reset di batas hari UTC', () {
      // 3 candle di hari-0 (epoch 0), lalu candle pertama hari-1 (86400000).
      final c = [
        _c(0, 10, 10),
        _c(3600000, 20, 10),
        _c(7200000, 30, 10),
        _c(86400000, 50, 10), // hari baru → reset
      ];
      final r = Vwap.compute(c, mode: VwapMode.anchoredDaily);
      // Candle pertama hari baru → VWAP = typical price-nya sendiri (50).
      expect(r.vwap[3], closeTo(50, 1e-9));
      // Sebelum reset, akumulatif (bukan 50).
      expect(r.vwap[2], closeTo(20, 1e-9)); // avg(10,20,30)
    });
  });
}
