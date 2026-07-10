import 'dart:math' as math;

import '../models/candle.dart';

/// Kumpulan indikator teknikal murni (tanpa dependency eksternal) yang bekerja
/// pada list [Candle] terurut menaik berdasarkan waktu.
///
/// Konvensi: setiap fungsi mengembalikan list sepanjang input; nilai yang
/// belum dapat dihitung (periode awal) diisi [double.nan].
class Indicators {
  Indicators._();

  static List<double> closes(List<Candle> c) =>
      c.map((e) => e.close).toList(growable: false);
  static List<double> highs(List<Candle> c) =>
      c.map((e) => e.high).toList(growable: false);
  static List<double> lows(List<Candle> c) =>
      c.map((e) => e.low).toList(growable: false);
  static List<double> volumes(List<Candle> c) =>
      c.map((e) => e.volume).toList(growable: false);

  // ---------------------------------------------------------------------------
  // Moving averages
  // ---------------------------------------------------------------------------

  /// Simple Moving Average.
  static List<double> sma(List<double> src, int period) {
    final out = List<double>.filled(src.length, double.nan);
    if (period <= 0 || src.length < period) return out;
    double sum = 0;
    for (int i = 0; i < src.length; i++) {
      sum += src[i];
      if (i >= period) sum -= src[i - period];
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  /// Exponential Moving Average. Seed memakai SMA periode pertama.
  static List<double> ema(List<double> src, int period) {
    final out = List<double>.filled(src.length, double.nan);
    if (period <= 0 || src.length < period) return out;
    final k = 2 / (period + 1);
    double seed = 0;
    for (int i = 0; i < period; i++) {
      seed += src[i];
    }
    double prev = seed / period;
    out[period - 1] = prev;
    for (int i = period; i < src.length; i++) {
      prev = (src[i] - prev) * k + prev;
      out[i] = prev;
    }
    return out;
  }

  /// Standar deviasi bergulir (populasi) untuk Bollinger.
  static List<double> rollingStd(List<double> src, int period) {
    final out = List<double>.filled(src.length, double.nan);
    if (src.length < period) return out;
    for (int i = period - 1; i < src.length; i++) {
      double mean = 0;
      for (int j = i - period + 1; j <= i; j++) {
        mean += src[j];
      }
      mean /= period;
      double variance = 0;
      for (int j = i - period + 1; j <= i; j++) {
        final d = src[j] - mean;
        variance += d * d;
      }
      out[i] = math.sqrt(variance / period);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // RSI (Wilder)
  // ---------------------------------------------------------------------------

  static List<double> rsi(List<double> src, int period) {
    final out = List<double>.filled(src.length, double.nan);
    if (src.length <= period) return out;
    double gain = 0, loss = 0;
    for (int i = 1; i <= period; i++) {
      final ch = src[i] - src[i - 1];
      if (ch >= 0) {
        gain += ch;
      } else {
        loss -= ch;
      }
    }
    double avgGain = gain / period;
    double avgLoss = loss / period;
    out[period] = _rsiFrom(avgGain, avgLoss);
    for (int i = period + 1; i < src.length; i++) {
      final ch = src[i] - src[i - 1];
      final g = ch > 0 ? ch : 0.0;
      final l = ch < 0 ? -ch : 0.0;
      avgGain = (avgGain * (period - 1) + g) / period;
      avgLoss = (avgLoss * (period - 1) + l) / period;
      out[i] = _rsiFrom(avgGain, avgLoss);
    }
    return out;
  }

  static double _rsiFrom(double avgGain, double avgLoss) {
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  // ---------------------------------------------------------------------------
  // MACD
  // ---------------------------------------------------------------------------

  static MacdResult macd(
    List<double> src, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    final emaFast = ema(src, fast);
    final emaSlow = ema(src, slow);
    final macdLine = List<double>.filled(src.length, double.nan);
    for (int i = 0; i < src.length; i++) {
      if (!emaFast[i].isNaN && !emaSlow[i].isNaN) {
        macdLine[i] = emaFast[i] - emaSlow[i];
      }
    }
    // Signal = EMA(macdLine) dihitung hanya pada bagian valid.
    final firstValid = macdLine.indexWhere((v) => !v.isNaN);
    final signalLine = List<double>.filled(src.length, double.nan);
    final hist = List<double>.filled(src.length, double.nan);
    if (firstValid != -1) {
      final valid = macdLine.sublist(firstValid);
      final sig = ema(valid, signal);
      for (int i = 0; i < sig.length; i++) {
        final idx = firstValid + i;
        signalLine[idx] = sig[i];
        if (!sig[i].isNaN) hist[idx] = macdLine[idx] - sig[i];
      }
    }
    return MacdResult(macdLine, signalLine, hist);
  }

  // ---------------------------------------------------------------------------
  // Bollinger Bands
  // ---------------------------------------------------------------------------

  static BollingerResult bollinger(
    List<double> src, {
    int period = 20,
    double mult = 2.0,
  }) {
    final mid = sma(src, period);
    final std = rollingStd(src, period);
    final upper = List<double>.filled(src.length, double.nan);
    final lower = List<double>.filled(src.length, double.nan);
    final bandwidth = List<double>.filled(src.length, double.nan);
    for (int i = 0; i < src.length; i++) {
      if (!mid[i].isNaN && !std[i].isNaN) {
        upper[i] = mid[i] + mult * std[i];
        lower[i] = mid[i] - mult * std[i];
        bandwidth[i] = mid[i] == 0 ? 0 : (upper[i] - lower[i]) / mid[i];
      }
    }
    return BollingerResult(mid, upper, lower, bandwidth);
  }

  // ---------------------------------------------------------------------------
  // ATR (Wilder)
  // ---------------------------------------------------------------------------

  static List<double> atr(List<Candle> c, int period) {
    final out = List<double>.filled(c.length, double.nan);
    if (c.length <= period) return out;
    final tr = List<double>.filled(c.length, double.nan);
    tr[0] = c[0].high - c[0].low;
    for (int i = 1; i < c.length; i++) {
      final h = c[i].high, l = c[i].low, pc = c[i - 1].close;
      tr[i] = [
        h - l,
        (h - pc).abs(),
        (l - pc).abs(),
      ].reduce(math.max);
    }
    double sum = 0;
    for (int i = 1; i <= period; i++) {
      sum += tr[i];
    }
    double prev = sum / period;
    out[period] = prev;
    for (int i = period + 1; i < c.length; i++) {
      prev = (prev * (period - 1) + tr[i]) / period;
      out[i] = prev;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // ADX / DMI (Wilder)
  // ---------------------------------------------------------------------------

  /// Average Directional Index + Directional Indicators (+DI/-DI), metode
  /// Wilder. Mengembalikan tiga list sepanjang input (awal = NaN).
  static AdxResult adx(List<Candle> c, {int period = 14}) {
    final n = c.length;
    final adxOut = List<double>.filled(n, double.nan);
    final plusOut = List<double>.filled(n, double.nan);
    final minusOut = List<double>.filled(n, double.nan);
    if (n <= period * 2) return AdxResult(adxOut, plusOut, minusOut);

    final tr = List<double>.filled(n, 0);
    final plusDm = List<double>.filled(n, 0);
    final minusDm = List<double>.filled(n, 0);
    for (int i = 1; i < n; i++) {
      final upMove = c[i].high - c[i - 1].high;
      final downMove = c[i - 1].low - c[i].low;
      plusDm[i] = (upMove > downMove && upMove > 0) ? upMove : 0;
      minusDm[i] = (downMove > upMove && downMove > 0) ? downMove : 0;
      final h = c[i].high, l = c[i].low, pc = c[i - 1].close;
      tr[i] = [h - l, (h - pc).abs(), (l - pc).abs()].reduce(math.max);
    }

    // Smoothing Wilder untuk TR, +DM, -DM.
    double trS = 0, plusS = 0, minusS = 0;
    for (int i = 1; i <= period; i++) {
      trS += tr[i];
      plusS += plusDm[i];
      minusS += minusDm[i];
    }

    final dx = List<double>.filled(n, double.nan);
    for (int i = period; i < n; i++) {
      if (i > period) {
        trS = trS - (trS / period) + tr[i];
        plusS = plusS - (plusS / period) + plusDm[i];
        minusS = minusS - (minusS / period) + minusDm[i];
      }
      final double plusDi = trS == 0 ? 0.0 : 100.0 * (plusS / trS);
      final double minusDi = trS == 0 ? 0.0 : 100.0 * (minusS / trS);
      plusOut[i] = plusDi;
      minusOut[i] = minusDi;
      final sum = plusDi + minusDi;
      dx[i] = sum == 0 ? 0.0 : 100.0 * ((plusDi - minusDi).abs() / sum);
    }

    // ADX = Wilder smoothing dari DX, dimulai period candle setelah DX pertama.
    final firstDx = period;
    final adxStart = firstDx + period; // butuh 'period' nilai DX untuk seed
    if (adxStart < n) {
      double seed = 0;
      for (int i = firstDx; i < firstDx + period; i++) {
        seed += dx[i];
      }
      double prev = seed / period;
      adxOut[adxStart - 1] = prev;
      for (int i = adxStart; i < n; i++) {
        prev = (prev * (period - 1) + dx[i]) / period;
        adxOut[i] = prev;
      }
    }
    return AdxResult(adxOut, plusOut, minusOut);
  }

  // ---------------------------------------------------------------------------
  // Stochastic Oscillator (%K, %D)
  // ---------------------------------------------------------------------------

  static StochasticResult stochastic(
    List<Candle> c, {
    int kPeriod = 14,
    int kSmooth = 3,
    int dPeriod = 3,
  }) {
    final rawK = List<double>.filled(c.length, double.nan);
    for (int i = kPeriod - 1; i < c.length; i++) {
      double hh = -double.infinity, ll = double.infinity;
      for (int j = i - kPeriod + 1; j <= i; j++) {
        hh = math.max(hh, c[j].high);
        ll = math.min(ll, c[j].low);
      }
      final range = hh - ll;
      rawK[i] = range == 0 ? 100 : ((c[i].close - ll) / range) * 100;
    }
    final k = sma(rawK.map((e) => e.isNaN ? 0.0 : e).toList(), kSmooth);
    // Bersihkan bagian awal yang tak valid.
    for (int i = 0; i < c.length; i++) {
      if (i < kPeriod - 1 + kSmooth - 1) k[i] = double.nan;
    }
    final d = sma(k.map((e) => e.isNaN ? 0.0 : e).toList(), dPeriod);
    for (int i = 0; i < c.length; i++) {
      if (i < kPeriod - 1 + kSmooth - 1 + dPeriod - 1) d[i] = double.nan;
    }
    return StochasticResult(k, d);
  }

  // ---------------------------------------------------------------------------
  // Swing points
  // ---------------------------------------------------------------------------

  /// Index swing low (pivot) dengan konfirmasi [left]/[right] candle di sisinya.
  static List<int> swingLows(List<Candle> c, {int left = 2, int right = 2}) {
    final out = <int>[];
    for (int i = left; i < c.length - right; i++) {
      bool pivot = true;
      for (int j = i - left; j <= i + right; j++) {
        if (j == i) continue;
        if (c[j].low <= c[i].low) {
          pivot = false;
          break;
        }
      }
      if (pivot) out.add(i);
    }
    return out;
  }

  static List<int> swingHighs(List<Candle> c, {int left = 2, int right = 2}) {
    final out = <int>[];
    for (int i = left; i < c.length - right; i++) {
      bool pivot = true;
      for (int j = i - left; j <= i + right; j++) {
        if (j == i) continue;
        if (c[j].high >= c[i].high) {
          pivot = false;
          break;
        }
      }
      if (pivot) out.add(i);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Candle patterns
  // ---------------------------------------------------------------------------

  static bool isBullishEngulfing(Candle prev, Candle cur) {
    final prevBear = prev.close < prev.open;
    final curBull = cur.close > cur.open;
    return prevBear &&
        curBull &&
        cur.close >= prev.open &&
        cur.open <= prev.close;
  }

  static bool isBearishEngulfing(Candle prev, Candle cur) {
    final prevBull = prev.close > prev.open;
    final curBear = cur.close < cur.open;
    return prevBull &&
        curBear &&
        cur.open >= prev.close &&
        cur.close <= prev.open;
  }

  /// Pin bar bullish: sumbu bawah panjang, badan kecil di sepertiga atas.
  static bool isBullishPinBar(Candle c) {
    final range = c.high - c.low;
    if (range <= 0) return false;
    final body = (c.close - c.open).abs();
    final lowerWick = math.min(c.open, c.close) - c.low;
    final upperWick = c.high - math.max(c.open, c.close);
    return lowerWick >= range * 0.55 &&
        body <= range * 0.35 &&
        upperWick <= range * 0.2;
  }

  /// Pin bar bearish: sumbu atas panjang.
  static bool isBearishPinBar(Candle c) {
    final range = c.high - c.low;
    if (range <= 0) return false;
    final body = (c.close - c.open).abs();
    final upperWick = c.high - math.max(c.open, c.close);
    final lowerWick = math.min(c.open, c.close) - c.low;
    return upperWick >= range * 0.55 &&
        body <= range * 0.35 &&
        lowerWick <= range * 0.2;
  }

  static double _body(Candle c) => (c.close - c.open).abs();

  /// Morning Star (reversal bullish 3-candle): candle 1 bearish bertubuh besar,
  /// candle 2 bertubuh kecil (indecision), candle 3 bullish yang menutup di atas
  /// titik tengah tubuh candle 1.
  static bool isMorningStar(Candle c1, Candle c2, Candle c3) {
    final bear1 = c1.close < c1.open;
    final small2 = _body(c2) <= _body(c1) * 0.5;
    final bull3 = c3.close > c3.open;
    final mid1 = (c1.open + c1.close) / 2;
    return bear1 && small2 && bull3 && c3.close > mid1;
  }

  /// Evening Star (reversal bearish 3-candle): kebalikan Morning Star.
  static bool isEveningStar(Candle c1, Candle c2, Candle c3) {
    final bull1 = c1.close > c1.open;
    final small2 = _body(c2) <= _body(c1) * 0.5;
    final bear3 = c3.close < c3.open;
    final mid1 = (c1.open + c1.close) / 2;
    return bull1 && small2 && bear3 && c3.close < mid1;
  }

  // ---------------------------------------------------------------------------
  // Level horizontal kunci (support/resistance)
  // ---------------------------------------------------------------------------

  /// Deteksi level horizontal "kunci" dari swing high/low dalam [lookback] candle
  /// terakhir. Sebuah level valid bila disentuh (high/low mendekati level dalam
  /// [tol] relatif) minimal [minTouches] kali. Dikembalikan terurut menaik.
  static List<double> keyHorizontalLevels(
    List<Candle> candles, {
    int lookback = 100,
    double tol = 0.005,
    int minTouches = 3,
  }) {
    if (candles.isEmpty) return const [];
    final start =
        candles.length > lookback ? candles.length - lookback : 0;
    final window = candles.sublist(start);
    // Kandidat = harga swing high & low.
    final pivots = <double>[];
    for (final i in swingHighs(window, left: 2, right: 2)) {
      pivots.add(window[i].high);
    }
    for (final i in swingLows(window, left: 2, right: 2)) {
      pivots.add(window[i].low);
    }
    if (pivots.isEmpty) return const [];

    // Kelompokkan pivot yang berdekatan (dalam [tol]) menjadi satu level.
    pivots.sort();
    final levels = <double>[];
    var clusterSum = pivots.first;
    var clusterCount = 1;
    var clusterRef = pivots.first;
    void flush() {
      if (clusterCount >= minTouches) levels.add(clusterSum / clusterCount);
    }

    for (int i = 1; i < pivots.length; i++) {
      final p = pivots[i];
      if ((p - clusterRef).abs() / clusterRef <= tol) {
        clusterSum += p;
        clusterCount++;
      } else {
        flush();
        clusterSum = p;
        clusterCount = 1;
      }
      clusterRef = p;
    }
    flush();
    return levels;
  }

  // ---------------------------------------------------------------------------
  // Volume Profile (fixed range)
  // ---------------------------------------------------------------------------

  /// Bangun volume profile pada [candles] dengan [bins] level harga.
  /// Volume tiap candle dibagi rata ke seluruh bin yang tercakup range H-L.
  static VolumeProfile volumeProfile(List<Candle> candles, {int bins = 50}) {
    if (candles.isEmpty) {
      return const VolumeProfile([], [], 0, 0, 0);
    }
    double lo = double.infinity, hi = -double.infinity;
    for (final c in candles) {
      lo = math.min(lo, c.low);
      hi = math.max(hi, c.high);
    }
    if (hi <= lo) hi = lo + 1e-9;
    final binSize = (hi - lo) / bins;
    final vol = List<double>.filled(bins, 0);
    for (final c in candles) {
      final startBin = ((c.low - lo) / binSize).floor().clamp(0, bins - 1);
      final endBin = ((c.high - lo) / binSize).floor().clamp(0, bins - 1);
      final span = (endBin - startBin) + 1;
      final share = c.volume / span;
      for (int b = startBin; b <= endBin; b++) {
        vol[b] += share;
      }
    }
    // Harga tengah tiap bin.
    final prices = List<double>.generate(
        bins, (i) => lo + binSize * (i + 0.5));
    int pocIndex = 0;
    for (int i = 1; i < bins; i++) {
      if (vol[i] > vol[pocIndex]) pocIndex = i;
    }
    return VolumeProfile(prices, vol, pocIndex, lo, hi);
  }
}

class MacdResult {
  final List<double> macd;
  final List<double> signal;
  final List<double> histogram;
  const MacdResult(this.macd, this.signal, this.histogram);
}

class BollingerResult {
  final List<double> middle;
  final List<double> upper;
  final List<double> lower;
  final List<double> bandwidth;
  const BollingerResult(this.middle, this.upper, this.lower, this.bandwidth);
}

class StochasticResult {
  final List<double> k;
  final List<double> d;
  const StochasticResult(this.k, this.d);
}

class AdxResult {
  final List<double> adx;
  final List<double> plusDi;
  final List<double> minusDi;
  const AdxResult(this.adx, this.plusDi, this.minusDi);
}

class VolumeProfile {
  final List<double> prices; // harga tengah tiap bin
  final List<double> volumes; // volume tiap bin
  final int pocIndex; // index Point of Control
  final double low;
  final double high;
  const VolumeProfile(
      this.prices, this.volumes, this.pocIndex, this.low, this.high);

  double get poc => prices.isEmpty ? 0 : prices[pocIndex];

  /// High Volume Nodes: bin dengan volume >= [factor] * volume rata-rata,
  /// diurutkan dari harga terendah ke tertinggi.
  List<double> highVolumeNodes({double factor = 1.5}) {
    if (volumes.isEmpty) return const [];
    final avg = volumes.reduce((a, b) => a + b) / volumes.length;
    final nodes = <double>[];
    for (int i = 0; i < volumes.length; i++) {
      if (volumes[i] >= avg * factor) nodes.add(prices[i]);
    }
    return nodes;
  }
}
