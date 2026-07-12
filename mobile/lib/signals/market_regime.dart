import '../config/app_config.dart';
import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';

/// Regime pasar hasil deteksi ADX + ATR.
///
/// - [trendingUp]/[trendingDown]: ADX ≥ ambang tren → ada arah dominan. Berlaku
///   WALAU ATR tinggi (ekspansi tren = peluang, bukan bahaya) → tetap trading.
/// - [ranging]: ADX rendah & ATR normal → sideways.
/// - [volatile]: ATR tinggi TANPA arah (ADX rendah) = chop/whipsaw → di-hard-hold.
/// - [transitional]: zona abu-abu ADX (histeresis) → penyesuaian kecil saja.
enum MarketRegime { trendingUp, trendingDown, ranging, volatile, transitional }

/// Karakter kecocokan sebuah "family" strategi terhadap kondisi pasar (BUKAN
/// arah BUY/SELL): mengikuti tren vs mean-reversion.
enum RegimeAffinity { trendFollowing, meanReverting }

/// Profil regime sebuah family — extensible: [primary] wajib, [secondary]
/// opsional (mis. `liquidity`: primer mean-reversion, sekunder trend-following
/// karena sweep bisa berlanjut jadi kontinuasi). Family yang TIDAK terdaftar di
/// [MarketRegimeDetector.familyProfiles] dianggap **benar-benar netral** (tak
/// kena penalti maupun bonus) agar family baru aman secara default.
class FamilyRegimeProfile {
  final RegimeAffinity primary;
  final RegimeAffinity? secondary;
  const FamilyRegimeProfile(this.primary, [this.secondary]);

  bool get isTrendFollowing =>
      primary == RegimeAffinity.trendFollowing ||
      secondary == RegimeAffinity.trendFollowing;
  bool get isMeanReverting =>
      primary == RegimeAffinity.meanReverting ||
      secondary == RegimeAffinity.meanReverting;
}

/// Snapshot regime untuk satu simbol pada candle tertutup terakhir.
class RegimeState {
  final MarketRegime regime;
  final double adx;
  final double atrPct;
  final double plusDi;
  final double minusDi;

  const RegimeState({
    required this.regime,
    required this.adx,
    required this.atrPct,
    required this.plusDi,
    required this.minusDi,
  });

  /// Regime jelas (bukan zona abu-abu). Transitional → penyesuaian minimal.
  bool get decisive => regime != MarketRegime.transitional;

  /// Hanya chop tanpa arah yang di-hard-hold (bukan setiap ATR tinggi).
  bool get hold => regime == MarketRegime.volatile;

  bool get isTrending =>
      regime == MarketRegime.trendingUp ||
      regime == MarketRegime.trendingDown;

  String get label {
    switch (regime) {
      case MarketRegime.trendingUp:
        return 'Tren Naik';
      case MarketRegime.trendingDown:
        return 'Tren Turun';
      case MarketRegime.ranging:
        return 'Sideways';
      case MarketRegime.volatile:
        return 'Volatil/Chop';
      case MarketRegime.transitional:
        return 'Transisi';
    }
  }

  static const RegimeState unknown = RegimeState(
    regime: MarketRegime.transitional,
    adx: 0,
    atrPct: 0,
    plusDi: 0,
    minusDi: 0,
  );
}

/// Filter regime pasar (Fase 3). MURNI & mudah diuji: hanya bergantung pada
/// candle + indikator yang sudah ada (ADX/ATR). Perannya HANYA menyesuaikan
/// confidence dan (untuk chop) menahan sinyal — TIDAK pernah menentukan arah
/// BUY/SELL (arah tetap dari core di [SignalEngine]).
class MarketRegimeDetector {
  MarketRegimeDetector._();

  /// Peta affinity family terpusat & extensible. Menambah strategi/family baru
  /// cukup satu entri di sini; yang tak terdaftar = netral penuh.
  static const Map<String, FamilyRegimeProfile> familyProfiles = {
    'trend': FamilyRegimeProfile(RegimeAffinity.trendFollowing),
    'breakout': FamilyRegimeProfile(RegimeAffinity.trendFollowing),
    'fib_retrace': FamilyRegimeProfile(RegimeAffinity.trendFollowing),
    'reversal': FamilyRegimeProfile(RegimeAffinity.meanReverting),
    'momentum': FamilyRegimeProfile(RegimeAffinity.meanReverting),
    'liquidity': FamilyRegimeProfile(
        RegimeAffinity.meanReverting, RegimeAffinity.trendFollowing),
  };

  /// Deteksi regime dari candle tertutup. Data kurang / indikator NaN →
  /// [RegimeState.unknown] (transitional; tak ada penyesuaian, tak menahan).
  static RegimeState detect(
    List<Candle> candles, {
    int adxPeriod = 14,
    int atrPeriod = 14,
    double? adxTrendMin,
    double? adxRangeMax,
    double? atrPctVolatile,
  }) {
    final trendMin = adxTrendMin ?? AppConfig.regimeAdxTrendMin;
    final rangeMax = adxRangeMax ?? AppConfig.regimeAdxRangeMax;
    final volPct = atrPctVolatile ?? AppConfig.regimeAtrPctVolatile;

    // ADX butuh > period*2 sampel; ATR butuh > period.
    if (candles.length <= adxPeriod * 2 + 1) return RegimeState.unknown;

    final adxRes = Indicators.adx(candles, period: adxPeriod);
    final atr = Indicators.atr(candles, atrPeriod);
    final last = candles.length - 1;
    final adx = adxRes.adx[last];
    final plusDi = adxRes.plusDi[last];
    final minusDi = adxRes.minusDi[last];
    final close = candles[last].close;
    if (adx.isNaN || plusDi.isNaN || minusDi.isNaN || atr[last].isNaN ||
        close <= 0) {
      return RegimeState.unknown;
    }
    final atrPct = atr[last] / close;

    // Presedensi: TREN diutamakan di atas volatilitas — ATR tinggi + ADX tinggi
    // = directional volatility (peluang), BUKAN hold.
    final MarketRegime regime;
    if (adx >= trendMin) {
      regime = plusDi >= minusDi
          ? MarketRegime.trendingUp
          : MarketRegime.trendingDown;
    } else if (atrPct >= volPct && adx <= rangeMax) {
      regime = MarketRegime.volatile; // chop tanpa arah → hard-hold
    } else if (adx <= rangeMax) {
      regime = MarketRegime.ranging;
    } else {
      regime = MarketRegime.transitional; // histeresis rangeMax..trendMin
    }

    return RegimeState(
      regime: regime,
      adx: adx,
      atrPct: atrPct,
      plusDi: plusDi,
      minusDi: minusDi,
    );
  }

  /// Skor mismatch sebuah family terhadap regime [ranging] (0 = cocok/netral,
  /// 1 = trend-following murni yang tak cocok di pasar sideways, 0.5 = primer
  /// tren tapi punya sisi mean-reversion → penalti tereduksi). Family tak
  /// terdaftar = 0 (netral penuh) agar family baru aman by-default.
  static double _rangeMismatchScore(String family) {
    final p = familyProfiles[family];
    if (p == null) return 0;
    if (p.primary == RegimeAffinity.meanReverting) return 0; // rumahnya range
    // primary trend-following:
    if (p.secondary == RegimeAffinity.meanReverting) return 0.5; // tereduksi
    return 1; // murni tren → tak cocok di range
  }

  /// SATU modifier confidence (poin), sudah di-clamp. TIDAK menentukan arah.
  /// - trending: searah tren → +bonus kecil; lawan tren → −penalti.
  /// - ranging: −penalti proporsional pangsa bobot family tren-kontinuasi.
  /// - transitional: −penalti kecil (sedikit hati-hati, tunable ke 0).
  /// - volatile: 0 di sini (ditangani sebagai hard-hold di engine).
  static double confidenceAdjustment(
    RegimeState r,
    String direction,
    List<(String family, double weight)> dirFamilies, {
    double? counterTrendPenalty,
    double? alignedBonus,
    double? rangeMismatchPenalty,
    double? transitionalPenalty,
    double? maxDown,
    double? maxUp,
  }) {
    final ctp = counterTrendPenalty ?? AppConfig.regimeCounterTrendPenalty;
    final bonus = alignedBonus ?? AppConfig.regimeAlignedBonus;
    final rmp = rangeMismatchPenalty ?? AppConfig.regimeRangeMismatchPenalty;
    final tp = transitionalPenalty ?? AppConfig.regimeTransitionalPenalty;
    final down = maxDown ?? AppConfig.regimeAdjMaxDown;
    final up = maxUp ?? AppConfig.regimeAdjMaxUp;

    double adj;
    switch (r.regime) {
      case MarketRegime.trendingUp:
        adj = direction == TradeDirection.buy ? bonus : -ctp;
        break;
      case MarketRegime.trendingDown:
        adj = direction == TradeDirection.sell ? bonus : -ctp;
        break;
      case MarketRegime.ranging:
        double wSum = 0, mSum = 0;
        for (final (family, w) in dirFamilies) {
          wSum += w;
          mSum += _rangeMismatchScore(family) * w;
        }
        final share = wSum > 0 ? mSum / wSum : 0.0;
        adj = -share * rmp;
        break;
      case MarketRegime.transitional:
        adj = -tp;
        break;
      case MarketRegime.volatile:
        adj = 0; // hard-hold di engine
        break;
    }
    return adj.clamp(-down, up);
  }
}
