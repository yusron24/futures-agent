import 'dart:math' as math;

import '../models/candle.dart';
import '../models/strategy_result.dart';

/// Metode/anchoring VWAP.
enum VwapMode {
  /// Bergulir pada jendela [VwapConfig.period] candle terakhir. Selalu
  /// terdefinisi, stabil di semua timeframe, tanpa logika sesi.
  rolling,

  /// Reset akumulasi tiap pergantian hari UTC (VWAP harian klasik).
  anchoredDaily,
}

/// Konfigurasi VWAP global yang dibaca BAIK oleh chart MAUPUN strategi, agar
/// hasil konsisten antara tampilan, signal engine, dan backtest. Diisi dari
/// [SettingsRepository] lewat `AppState.applyVwapSettings()`. Nilai default aman
/// sehingga unit test dapat memakai VWAP tanpa setup.
class VwapConfig {
  VwapConfig._();

  static VwapMode mode = VwapMode.rolling;
  static int period = 20;
  static double mult1 = 1.0;
  static double mult2 = 2.0;
  static double mult3 = 3.0;

  /// Bila false, strategi tidak menerapkan konfluens VWAP (perilaku seperti
  /// sebelum VWAP). Tidak memengaruhi tampilan chart.
  static bool enabledForSignals = true;

  static VwapMode modeFromString(String s) =>
      s == 'anchored' ? VwapMode.anchoredDaily : VwapMode.rolling;

  static String modeToString(VwapMode m) =>
      m == VwapMode.anchoredDaily ? 'anchored' : 'rolling';
}

/// Nilai VWAP + 3 band pada satu candle.
class VwapPoint {
  final double vwap;
  final double upper1;
  final double upper2;
  final double upper3;
  final double lower1;
  final double lower2;
  final double lower3;
  const VwapPoint(this.vwap, this.upper1, this.upper2, this.upper3,
      this.lower1, this.lower2, this.lower3);

  bool get isValid => !vwap.isNaN;
}

/// Hasil VWAP: 7 deret sepanjang input (NaN saat belum dapat dihitung).
class VwapResult {
  final List<double> vwap;
  final List<double> upper1;
  final List<double> upper2;
  final List<double> upper3;
  final List<double> lower1;
  final List<double> lower2;
  final List<double> lower3;
  const VwapResult(this.vwap, this.upper1, this.upper2, this.upper3,
      this.lower1, this.lower2, this.lower3);

  int get length => vwap.length;

  VwapPoint? at(int i) {
    if (i < 0 || i >= vwap.length || vwap[i].isNaN) return null;
    return VwapPoint(vwap[i], upper1[i], upper2[i], upper3[i], lower1[i],
        lower2[i], lower3[i]);
  }

  /// Titik valid paling akhir (nilai terbaru).
  VwapPoint? get last {
    for (int i = vwap.length - 1; i >= 0; i--) {
      final p = at(i);
      if (p != null) return p;
    }
    return null;
  }

  /// Apakah [price] searah bias VWAP untuk [direction] (BUY di atas / SELL di
  /// bawah VWAP). Bila VWAP belum tersedia → true (tidak memblokir).
  bool isAligned(String direction, double price) {
    final p = last;
    if (p == null) return true;
    if (direction == TradeDirection.buy) return price >= p.vwap;
    if (direction == TradeDirection.sell) return price <= p.vwap;
    return true;
  }

  /// Harga terlalu jauh dari VWAP (di luar band ke-3) → overextended.
  bool overExtension(double price) {
    final p = last;
    if (p == null) return false;
    return price > p.upper3 || price < p.lower3;
  }
}

/// Ringkasan konfluens VWAP untuk dipakai strategi (konfirmasi, bukan sumber
/// keputusan tunggal).
class VwapConfluence {
  /// VWAP tersedia (candle cukup) untuk dinilai.
  final bool available;

  /// Harga di sisi benar VWAP untuk arah trade (BUY di atas / SELL di bawah).
  final bool aligned;

  /// Harga di luar band ke-3 (terlalu jauh dari VWAP → overextended).
  final bool overExtended;

  /// Nilai VWAP terbaru (NaN bila tidak tersedia).
  final double vwapValue;

  /// Tingkat perlawanan harga terhadap VWAP (untuk soft-veto bertingkat):
  /// 0 = searah/aligned; 1 = sisi salah tapi dalam band-1; 2 = menembus band-1;
  /// 3 = menembus band-2 (invalidasi struktural).
  final int oppositionBand;

  const VwapConfluence({
    required this.available,
    required this.aligned,
    required this.overExtended,
    required this.vwapValue,
    this.oppositionBand = 0,
  });

  /// Invalidasi struktural jelas: harga menembus band-2 di sisi salah.
  bool get hardOppose => oppositionBand >= 3;

  /// Sesuaikan [confidence] (0..100): bonus bila searah VWAP, penalti bila
  /// melawan, penalti tambahan bila overextended.
  double adjust(
    double confidence, {
    double bonus = 8,
    double penalty = 15,
    double overPenalty = 8,
  }) {
    if (!available) return confidence.clamp(0, 100);
    var c = confidence + (aligned ? bonus : -penalty);
    if (overExtended) c -= overPenalty;
    return c.clamp(0, 100);
  }

  /// Penyesuaian BERTINGKAT (soft-veto): aligned → bonus kecil; band-1 → penalti
  /// ringan; band-2 → penalti besar; band-3 sebaiknya sudah di-veto pemanggil.
  double gradedAdjust(
    double confidence, {
    double alignedBonus = 6,
    double band1 = 8,
    double band2 = 20,
    double overPenalty = 8,
  }) {
    if (!available) return confidence.clamp(0, 100);
    var c = confidence;
    switch (oppositionBand) {
      case 0:
        c += alignedBonus;
        break;
      case 1:
        c -= band1;
        break;
      default: // 2 atau 3
        c -= band2;
    }
    if (overExtended) c -= overPenalty;
    return c.clamp(0, 100);
  }
}

/// Perhitungan VWAP + band deviasi standar tertimbang volume.
class Vwap {
  Vwap._();

  /// Konfluens VWAP untuk sebuah arah & harga entry pada [candles]. Memakai
  /// [VwapConfig] aktif sehingga konsisten dengan chart.
  static VwapConfluence confluenceOf(
    List<Candle> candles,
    String direction,
    double price,
  ) {
    final r = compute(candles);
    final p = r.last;
    if (p == null) {
      return const VwapConfluence(
        available: false,
        aligned: true,
        overExtended: false,
        vwapValue: double.nan,
      );
    }
    final buy = direction == TradeDirection.buy;
    final sell = direction == TradeDirection.sell;
    final aligned = buy
        ? price >= p.vwap
        : sell
            ? price <= p.vwap
            : true;
    // Tingkat perlawanan: seberapa jauh harga di sisi SALAH VWAP.
    int band = 0;
    if (!aligned) {
      if (buy) {
        band = price < p.lower2 ? 3 : (price < p.lower1 ? 2 : 1);
      } else if (sell) {
        band = price > p.upper2 ? 3 : (price > p.upper1 ? 2 : 1);
      }
    }
    return VwapConfluence(
      available: true,
      aligned: aligned,
      overExtended: price > p.upper3 || price < p.lower3,
      vwapValue: p.vwap,
      oppositionBand: band,
    );
  }

  static VwapResult compute(
    List<Candle> c, {
    VwapMode? mode,
    int? period,
    double? mult1,
    double? mult2,
    double? mult3,
  }) {
    final m = mode ?? VwapConfig.mode;
    final per = math.max(1, period ?? VwapConfig.period);
    final k1 = mult1 ?? VwapConfig.mult1;
    final k2 = mult2 ?? VwapConfig.mult2;
    final k3 = mult3 ?? VwapConfig.mult3;

    final n = c.length;
    final vwap = List<double>.filled(n, double.nan);
    final u1 = List<double>.filled(n, double.nan);
    final u2 = List<double>.filled(n, double.nan);
    final u3 = List<double>.filled(n, double.nan);
    final l1 = List<double>.filled(n, double.nan);
    final l2 = List<double>.filled(n, double.nan);
    final l3 = List<double>.filled(n, double.nan);
    if (n == 0) return VwapResult(vwap, u1, u2, u3, l1, l2, l3);

    // Precompute typical price & volume.
    final tp = List<double>.filled(n, 0);
    final vol = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      tp[i] = (c[i].high + c[i].low + c[i].close) / 3.0;
      vol[i] = c[i].volume.isFinite && c[i].volume > 0 ? c[i].volume : 0;
    }

    void setBands(int i, double mean, double std) {
      vwap[i] = mean;
      u1[i] = mean + k1 * std;
      u2[i] = mean + k2 * std;
      u3[i] = mean + k3 * std;
      l1[i] = mean - k1 * std;
      l2[i] = mean - k2 * std;
      l3[i] = mean - k3 * std;
    }

    if (m == VwapMode.rolling) {
      for (int i = per - 1; i < n; i++) {
        double spv = 0, sv = 0, stp = 0;
        for (int j = i - per + 1; j <= i; j++) {
          spv += tp[j] * vol[j];
          sv += vol[j];
          stp += tp[j];
        }
        final weighted = sv > 0;
        final mean = weighted ? spv / sv : stp / per;
        double varc = 0;
        for (int j = i - per + 1; j <= i; j++) {
          final d = tp[j] - mean;
          varc += weighted ? vol[j] * d * d : d * d;
        }
        varc = weighted ? varc / sv : varc / per;
        setBands(i, mean, math.sqrt(math.max(0, varc)));
      }
    } else {
      // Anchored harian (UTC): reset akumulasi tiap pergantian hari.
      double cpv = 0, cv = 0, cpv2 = 0; // tertimbang volume
      double stp = 0, stp2 = 0; // fallback tanpa bobot
      int cnt = 0;
      int curDay = _dayKey(c[0]);
      for (int i = 0; i < n; i++) {
        final day = _dayKey(c[i]);
        if (i == 0 || day != curDay) {
          cpv = 0;
          cv = 0;
          cpv2 = 0;
          stp = 0;
          stp2 = 0;
          cnt = 0;
          curDay = day;
        }
        cpv += tp[i] * vol[i];
        cv += vol[i];
        cpv2 += vol[i] * tp[i] * tp[i];
        stp += tp[i];
        stp2 += tp[i] * tp[i];
        cnt++;
        final weighted = cv > 0;
        final mean = weighted ? cpv / cv : stp / cnt;
        final varc =
            weighted ? cpv2 / cv - mean * mean : stp2 / cnt - mean * mean;
        setBands(i, mean, math.sqrt(math.max(0, varc)));
      }
    }

    return VwapResult(vwap, u1, u2, u3, l1, l2, l3);
  }

  static int _dayKey(Candle c) {
    final d = c.openDateTime; // UTC
    return d.year * 10000 + d.month * 100 + d.day;
  }
}
