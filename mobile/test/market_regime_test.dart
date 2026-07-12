import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/config/app_config.dart';
import 'package:scalp_signals/models/candle.dart';
import 'package:scalp_signals/models/strategy_result.dart';
import 'package:scalp_signals/signals/market_regime.dart';

Candle _c(int i, double o, double h, double l, double c) => Candle(
      openTime: i * 3600000,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: 100,
      closeTime: i * 3600000 + 1,
    );

/// Tren naik bersih, ATR normal → ADX tinggi, +DI > −DI.
List<Candle> _uptrend() {
  final out = <Candle>[];
  for (int i = 0; i < 60; i++) {
    final o = 100 + i * 1.0;
    final c = o + 0.8;
    out.add(_c(i, o, c + 0.2, o - 0.2, c));
  }
  return out;
}

/// Tren turun bersih → ADX tinggi, −DI > +DI.
List<Candle> _downtrend() {
  final out = <Candle>[];
  for (int i = 0; i < 60; i++) {
    final o = 200 - i * 1.0;
    final c = o - 0.8;
    out.add(_c(i, o, o + 0.2, c - 0.2, c));
  }
  return out;
}

/// Tren naik kuat DENGAN ATR tinggi (range besar) → directional volatility.
/// Harus tetap trendingUp (BUKAN volatile/hold).
List<Candle> _uptrendHighAtr() {
  final out = <Candle>[];
  for (int i = 0; i < 60; i++) {
    final o = 100 + i * 3.0;
    final c = o + 6.0;
    out.add(_c(i, o, c + 8.0, o - 8.0, c)); // range ~22
  }
  return out;
}

/// Sideways rapat, ATR kecil → ADX rendah, atrPct rendah → ranging.
List<Candle> _ranging() {
  final out = <Candle>[];
  for (int i = 0; i < 80; i++) {
    final up = i % 2 == 0;
    final o = 100 + (up ? -0.15 : 0.15);
    final c = 100 + (up ? 0.15 : -0.15);
    final j = (i % 4) * 0.05; // variasi kecil agar DM tak nol
    final hi = (o > c ? o : c) + 0.1 + j;
    final lo = (o < c ? o : c) - 0.1 - j;
    out.add(_c(i, o, hi, lo, c));
  }
  return out;
}

/// Chop volatil: ayunan besar bolak-balik tanpa arah → ATR tinggi, ADX rendah.
List<Candle> _volatileChop() {
  final out = <Candle>[];
  for (int i = 0; i < 80; i++) {
    final up = i % 2 == 0;
    final amp = 6.0 + (i % 5); // 6..10, bervariasi
    final o = 100 + (up ? -amp / 2 : amp / 2);
    final c = 100 + (up ? amp / 2 : -amp / 2);
    final off = 1.0 + (i % 3); // extrem bervariasi → DM tak nol, seimbang
    final hi = (o > c ? o : c) + off;
    final lo = (o < c ? o : c) - off;
    out.add(_c(i, o, hi, lo, c));
  }
  return out;
}

void main() {
  group('MarketRegimeDetector.detect', () {
    test('tren naik bersih → trendingUp (+DI > −DI), tidak hold', () {
      final r = MarketRegimeDetector.detect(_uptrend());
      expect(r.regime, MarketRegime.trendingUp);
      expect(r.plusDi, greaterThan(r.minusDi));
      expect(r.hold, false);
      expect(r.adx, greaterThanOrEqualTo(AppConfig.regimeAdxTrendMin));
    });

    test('tren turun bersih → trendingDown', () {
      final r = MarketRegimeDetector.detect(_downtrend());
      expect(r.regime, MarketRegime.trendingDown);
      expect(r.minusDi, greaterThan(r.plusDi));
      expect(r.hold, false);
    });

    test('tren + ATR tinggi → tetap trending, TIDAK di-hold (revisi #1)', () {
      final r = MarketRegimeDetector.detect(_uptrendHighAtr());
      expect(r.isTrending, true);
      expect(r.regime, MarketRegime.trendingUp);
      expect(r.atrPct, greaterThan(AppConfig.regimeAtrPctVolatile));
      expect(r.hold, false);
    });

    test('sideways rapat → ranging, ATR% rendah, tidak hold', () {
      final r = MarketRegimeDetector.detect(_ranging());
      expect(r.regime, MarketRegime.ranging);
      expect(r.atrPct, lessThan(AppConfig.regimeAtrPctVolatile));
      expect(r.hold, false);
    });

    test('chop volatil (ATR tinggi tanpa arah) → volatile & hold', () {
      final r = MarketRegimeDetector.detect(_volatileChop());
      expect(r.regime, MarketRegime.volatile);
      expect(r.atrPct, greaterThanOrEqualTo(AppConfig.regimeAtrPctVolatile));
      expect(r.adx, lessThanOrEqualTo(AppConfig.regimeAdxRangeMax));
      expect(r.hold, true);
    });

    test('data kurang → transitional (netral, tidak hold)', () {
      final few = List.generate(20, (i) => _c(i, 100, 101, 99, 100));
      final r = MarketRegimeDetector.detect(few);
      expect(r.regime, MarketRegime.transitional);
      expect(r.decisive, false);
      expect(r.hold, false);
    });
  });

  group('MarketRegimeDetector.confidenceAdjustment', () {
    RegimeState state(MarketRegime m) => RegimeState(
        regime: m, adx: 30, atrPct: 0.02, plusDi: 30, minusDi: 10);

    test('trendingUp: searah (BUY) → +bonus; lawan (SELL) → −penalti', () {
      final up = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.trendingUp), TradeDirection.buy, []);
      expect(up, closeTo(AppConfig.regimeAlignedBonus, 1e-9));
      final down = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.trendingUp), TradeDirection.sell, []);
      expect(down, closeTo(-AppConfig.regimeCounterTrendPenalty, 1e-9));
    });

    test('bonus searah ter-clamp ≤ regimeAdjMaxUp', () {
      final v = MarketRegimeDetector.confidenceAdjustment(
        state(MarketRegime.trendingUp), TradeDirection.buy, [],
        alignedBonus: 999,
      );
      expect(v, closeTo(AppConfig.regimeAdjMaxUp, 1e-9));
    });

    test('ranging: family trend → penalti penuh; reversal/liquidity → 0', () {
      final trend = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.ranging), TradeDirection.buy, [('trend', 1.0)]);
      expect(trend, closeTo(-AppConfig.regimeRangeMismatchPenalty, 1e-9));

      final rev = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.ranging), TradeDirection.buy, [('reversal', 1.0)]);
      expect(rev, closeTo(0, 1e-9));

      // liquidity: primary mean-reversion → rumahnya pasar range → tanpa penalti.
      final liq = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.ranging), TradeDirection.buy, [('liquidity', 1.0)]);
      expect(liq, closeTo(0, 1e-9));
    });

    test('ranging: penalti proporsional pangsa bobot family trend', () {
      // 50% bobot family trend, 50% reversal → setengah penalti.
      final v = MarketRegimeDetector.confidenceAdjustment(
        state(MarketRegime.ranging),
        TradeDirection.buy,
        [('trend', 1.0), ('reversal', 1.0)],
      );
      expect(v, closeTo(-AppConfig.regimeRangeMismatchPenalty * 0.5, 1e-9));
    });

    test('ranging: family tak dikenal → benar-benar netral (0)', () {
      final v = MarketRegimeDetector.confidenceAdjustment(
        state(MarketRegime.ranging),
        TradeDirection.buy,
        [('family_baru_belum_terdaftar', 1.0)],
      );
      expect(v, closeTo(0, 1e-9));
    });

    test('transitional → penalti kecil (revisi #2, tunable)', () {
      final v = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.transitional), TradeDirection.buy, []);
      expect(v, closeTo(-AppConfig.regimeTransitionalPenalty, 1e-9));
    });

    test('volatile → 0 di sini (hard-hold ditangani engine)', () {
      final v = MarketRegimeDetector.confidenceAdjustment(
          state(MarketRegime.volatile), TradeDirection.buy, [('trend', 1.0)]);
      expect(v, closeTo(0, 1e-9));
    });

    test('penalti selalu ter-clamp ≥ −regimeAdjMaxDown', () {
      final v = MarketRegimeDetector.confidenceAdjustment(
        state(MarketRegime.ranging), TradeDirection.buy, [('trend', 1.0)],
        rangeMismatchPenalty: 999,
      );
      expect(v, closeTo(-AppConfig.regimeAdjMaxDown, 1e-9));
    });
  });
}
