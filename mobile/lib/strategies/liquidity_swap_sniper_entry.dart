import 'dart:math' as math;

import '../indicators/indicators.dart';
import '../indicators/vwap.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 6 — Liquidity Swap Sniper Entry (Smart Money Concepts).
///
/// Menunggu urutan konfirmasi penuh sebelum entry sehingga memangkas entry
/// palsu di Order Block:
///   1. Filter tren wajib EMA50 vs EMA200 (hanya searah tren).
///   2. Order Block (demand/supply) yang diikuti imbalance & belum dimitigasi.
///   3. Liquidity Sweep — sapuan swing low/high sebelumnya lalu di-reclaim.
///   4. Change of Character (CHoCH) — close menembus struktur minor terakhir.
///   5. Imbalance / Fair Value Gap (FVG) dengan displacement kuat.
///   6. Entry limit pada candle opposite terakhir sebelum imbalance (atau area
///      imbalance bila candle opposite terlalu besar).
///
/// Catatan arsitektur: sistem ini mengevaluasi strategi pada SATU timeframe
/// aktif (yang dipilih pengguna). Konsep multi-timeframe HTF→LTF dirender pada
/// timeframe aktif melalui struktur swing (HTF = tren EMA + struktur besar,
/// LTF = reaksi/sweep/imbalance terbaru). Output tetap [StrategyResult] standar
/// sehingga diproses confidence engine & risk manager tanpa perubahan arsitektur.
class LiquiditySwapSniperEntry extends Strategy {
  @override
  String get id => 'liquidity_swap_sniper';
  @override
  StrategyTier get tier => StrategyTier.experimental;
  @override
  String get family => 'liquidity';
  @override
  String get name => 'Liquidity Swap Sniper Entry';
  @override
  String get description =>
      'SMC: sweep likuiditas + CHoCH + imbalance searah tren EMA50/200. '
      'Entry limit di order block. RR ≥ 1:2,5.';
  @override
  int get minCandles => 230;

  static const int emaFast = 50;
  static const int emaTrend = 200;
  static const int atrPeriod = 14;

  // Ambang deteksi.
  static const int fvgLookback = 16; // imbalance harus baru
  static const int obLookback = 6; // candle opposite dekat displacement
  static const double dispBodyAtr = 0.5; // badan displacement ≥ 0,5×ATR
  static const double fvgGapAtr = 0.15; // celah FVG ≥ 0,15×ATR
  static const double slBufferAtr = 0.5; // buffer SL dari sweep
  static const double maxSlPct = 0.05; // sweep terlalu dalam bila SL >5%
  static const double maxEntryDistPct = 0.06; // entry terlalu jauh dari harga
  static const double rr = 2.5;
  static const double minScore = 75; // ambang internal strategi

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final closes = Indicators.closes(candles);
    final ema50 = Indicators.ema(closes, emaFast);
    final ema200 = Indicators.ema(closes, emaTrend);
    final atr = Indicators.atr(candles, atrPeriod);
    final volumes = Indicators.volumes(candles);

    final last = candles.length - 1;
    if (ema50[last].isNaN || ema200[last].isNaN || atr[last].isNaN) {
      return StrategyResult.none(id, name);
    }

    // STEP 1 — tren wajib jelas (tidak boleh crossing/tidak jelas).
    final bull = ema50[last] > ema200[last];
    final bear = ema50[last] < ema200[last];
    if (!bull && !bear) {
      return StrategyResult.none(id, name, note: 'Tren EMA tidak jelas');
    }

    return bull
        ? _evaluateBull(candles, atr, volumes)
        : _evaluateBear(candles, atr, volumes);
  }

  // ---------------------------------------------------------------------------
  // BUY (demand)
  // ---------------------------------------------------------------------------
  StrategyResult _evaluateBull(
    List<Candle> c,
    List<double> atr,
    List<double> volumes,
  ) {
    final last = c.length - 1;
    final atrNow = atr[last];
    final price = c[last].close;
    if (atrNow <= 0) return StrategyResult.none(id, name);

    // STEP 7 (dicari lebih dulu sebagai jangkar) — Bullish FVG + displacement.
    // FVG bullish 3-candle: high[d-1] < low[d+1], candle d = displacement bullish.
    int? d;
    double gap = 0;
    for (int i = last - 1; i >= math.max(3, last - fvgLookback); i--) {
      final g = c[i + 1].low - c[i - 1].high; // celah imbalance
      if (g <= 0) continue;
      final disp = c[i];
      final strongBody =
          disp.close > disp.open && (disp.close - disp.open) >= dispBodyAtr * atrNow;
      if (strongBody && g >= fvgGapAtr * atrNow) {
        d = i;
        gap = g;
        break;
      }
    }
    if (d == null) {
      return StrategyResult.none(id, name, note: 'Tanpa imbalance/FVG bullish');
    }
    final dispIdx = d;

    // STEP 2 & 8 — Order Block = candle bearish terakhir sebelum displacement.
    int obIdx = dispIdx - 1;
    for (int i = dispIdx - 1; i >= math.max(0, dispIdx - obLookback); i--) {
      if (c[i].close < c[i].open) {
        obIdx = i;
        break;
      }
    }
    final ob = c[obIdx];

    // Order block belum dimitigasi/rusak: tidak ada close di bawah OB low sesudahnya.
    for (int j = obIdx + 1; j <= last; j++) {
      if (c[j].close < ob.low - slBufferAtr * atrNow) {
        return StrategyResult.none(id, name,
            note: 'Order block sudah dimitigasi/tembus');
      }
    }

    // STEP 5 & 6 — Liquidity Sweep: swing low sebelum displacement yang low-nya
    // ditembus lalu di-reclaim (close kembali di atas level).
    final lows = Indicators.swingLows(c, left: 2, right: 2)
        .where((i) => i < dispIdx)
        .toList();
    if (lows.isEmpty) {
      return StrategyResult.none(id, name, note: 'Tidak ada swing low likuiditas');
    }
    double? sweepLow;
    for (final li in lows.reversed) {
      final level = c[li].low;
      double minLow = double.infinity;
      int minIdx = li;
      for (int j = li + 1; j <= dispIdx; j++) {
        if (c[j].low < minLow) {
          minLow = c[j].low;
          minIdx = j;
        }
      }
      final took = minLow < level; // menyapu likuiditas di bawah swing low
      bool reclaim = false;
      for (int j = minIdx; j <= dispIdx; j++) {
        if (c[j].close > level) {
          reclaim = true;
          break;
        }
      }
      if (took && reclaim) {
        sweepLow = minLow;
        break;
      }
    }
    if (sweepLow == null) {
      return StrategyResult.none(id, name, note: 'Liquidity belum disapu');
    }

    // STEP 4 — CHoCH: close menembus swing high minor terakhir sebelum displacement.
    final highs = Indicators.swingHighs(c, left: 2, right: 2)
        .where((i) => i < dispIdx)
        .toList();
    if (highs.isEmpty) {
      return StrategyResult.none(id, name, note: 'Struktur CHoCH tak terbentuk');
    }
    final lhLevel = c[highs.last].high;
    bool choch = false;
    double breakMargin = 0;
    for (int j = dispIdx; j <= last; j++) {
      if (c[j].close > lhLevel) {
        choch = true;
        breakMargin = math.max(breakMargin, c[j].close - lhLevel);
      }
    }
    if (!choch) {
      return StrategyResult.none(id, name, note: 'Belum ada CHoCH bullish');
    }
    final strongBos = breakMargin >= 0.1 * atrNow;

    // STEP 8 — Entry limit di OB (candle opposite). Bila OB terlalu besar → area imbalance.
    double entry;
    if ((ob.high - ob.low) > 1.5 * atrNow) {
      entry = (c[dispIdx - 1].high + c[dispIdx + 1].low) / 2; // mid FVG
    } else {
      entry = ob.high;
    }
    if (entry > price) entry = price; // buy limit tidak boleh di atas harga
    if ((price - entry) / price > maxEntryDistPct) {
      return StrategyResult.none(id, name, note: 'Entry terlalu jauh dari OB');
    }

    // Stop loss + take profit.
    final sl = sweepLow - slBufferAtr * atrNow;
    final risk = entry - sl;
    if (risk <= 0) return StrategyResult.none(id, name);
    if (risk / entry > maxSlPct) {
      return StrategyResult.none(id, name, note: 'Sweep terlalu dalam (SL >5%)');
    }
    final tp = entry + rr * risk;

    final score = _score(
      choch: true,
      strongBos: strongBos,
      atrHealthy: _atrHealthy(atrNow, price),
      volumeUp: _volumeIncreasing(volumes, dispIdx),
    );
    if (score < minScore) {
      return StrategyResult.none(id, name, note: 'Skor SMC < ambang');
    }

    // Konfluens VWAP: sebagai magnet/target & filter over-extension.
    final vwap = VwapConfig.enabledForSignals
        ? Vwap.confluenceOf(c, TradeDirection.buy, entry)
        : null;
    var conf = score;
    if (vwap != null) {
      conf = vwap.adjust(conf, bonus: 6, penalty: 10, overPenalty: 8);
    }
    final ind = <String, String>{
      'Tren': 'BULLISH (EMA50>EMA200)',
      'Order Block': '${ob.low.toStringAsFixed(4)}–${ob.high.toStringAsFixed(4)}',
      'Liquidity Sweep': sweepLow.toStringAsFixed(4),
      'CHoCH > ': lhLevel.toStringAsFixed(4),
      'Imbalance(FVG)': gap.toStringAsFixed(4),
      'Entry (limit)': entry.toStringAsFixed(4),
      'Skor SMC': score.toStringAsFixed(0),
      'RR': '1:2,5',
    };
    if (vwap != null && vwap.available) {
      ind['VWAP (target)'] = vwap.vwapValue.toStringAsFixed(4);
    }
    return StrategyResult(
      strategyId: id,
      strategyName: name,
      fired: true,
      direction: TradeDirection.buy,
      confidence: conf,
      entry: entry,
      stopLoss: sl,
      takeProfit: tp,
      indicators: ind,
      note: 'Sweep low → CHoCH bullish → imbalance → buy limit di OB',
    );
  }

  // ---------------------------------------------------------------------------
  // SELL (supply) — cermin dari BUY
  // ---------------------------------------------------------------------------
  StrategyResult _evaluateBear(
    List<Candle> c,
    List<double> atr,
    List<double> volumes,
  ) {
    final last = c.length - 1;
    final atrNow = atr[last];
    final price = c[last].close;
    if (atrNow <= 0) return StrategyResult.none(id, name);

    // Bearish FVG: low[d-1] > high[d+1], candle d = displacement bearish.
    int? d;
    double gap = 0;
    for (int i = last - 1; i >= math.max(3, last - fvgLookback); i--) {
      final g = c[i - 1].low - c[i + 1].high;
      if (g <= 0) continue;
      final disp = c[i];
      final strongBody =
          disp.close < disp.open && (disp.open - disp.close) >= dispBodyAtr * atrNow;
      if (strongBody && g >= fvgGapAtr * atrNow) {
        d = i;
        gap = g;
        break;
      }
    }
    if (d == null) {
      return StrategyResult.none(id, name, note: 'Tanpa imbalance/FVG bearish');
    }
    final dispIdx = d;

    // Order block = candle bullish terakhir sebelum displacement.
    int obIdx = dispIdx - 1;
    for (int i = dispIdx - 1; i >= math.max(0, dispIdx - obLookback); i--) {
      if (c[i].close > c[i].open) {
        obIdx = i;
        break;
      }
    }
    final ob = c[obIdx];

    // OB belum dimitigasi: tidak ada close di atas OB high sesudahnya.
    for (int j = obIdx + 1; j <= last; j++) {
      if (c[j].close > ob.high + slBufferAtr * atrNow) {
        return StrategyResult.none(id, name,
            note: 'Order block sudah dimitigasi/tembus');
      }
    }

    // Liquidity sweep: swing high sebelum displacement yang high-nya ditembus lalu reclaim.
    final highs = Indicators.swingHighs(c, left: 2, right: 2)
        .where((i) => i < dispIdx)
        .toList();
    if (highs.isEmpty) {
      return StrategyResult.none(id, name, note: 'Tidak ada swing high likuiditas');
    }
    double? sweepHigh;
    for (final hi in highs.reversed) {
      final level = c[hi].high;
      double maxHigh = -double.infinity;
      int maxIdx = hi;
      for (int j = hi + 1; j <= dispIdx; j++) {
        if (c[j].high > maxHigh) {
          maxHigh = c[j].high;
          maxIdx = j;
        }
      }
      final took = maxHigh > level;
      bool reclaim = false;
      for (int j = maxIdx; j <= dispIdx; j++) {
        if (c[j].close < level) {
          reclaim = true;
          break;
        }
      }
      if (took && reclaim) {
        sweepHigh = maxHigh;
        break;
      }
    }
    if (sweepHigh == null) {
      return StrategyResult.none(id, name, note: 'Liquidity belum disapu');
    }

    // CHoCH: close menembus swing low minor terakhir sebelum displacement.
    final lows = Indicators.swingLows(c, left: 2, right: 2)
        .where((i) => i < dispIdx)
        .toList();
    if (lows.isEmpty) {
      return StrategyResult.none(id, name, note: 'Struktur CHoCH tak terbentuk');
    }
    final hlLevel = c[lows.last].low;
    bool choch = false;
    double breakMargin = 0;
    for (int j = dispIdx; j <= last; j++) {
      if (c[j].close < hlLevel) {
        choch = true;
        breakMargin = math.max(breakMargin, hlLevel - c[j].close);
      }
    }
    if (!choch) {
      return StrategyResult.none(id, name, note: 'Belum ada CHoCH bearish');
    }
    final strongBos = breakMargin >= 0.1 * atrNow;

    // Entry limit di OB (candle opposite). Bila OB terlalu besar → area imbalance.
    double entry;
    if ((ob.high - ob.low) > 1.5 * atrNow) {
      entry = (c[dispIdx - 1].low + c[dispIdx + 1].high) / 2;
    } else {
      entry = ob.low;
    }
    if (entry < price) entry = price; // sell limit tidak boleh di bawah harga
    if ((entry - price) / price > maxEntryDistPct) {
      return StrategyResult.none(id, name, note: 'Entry terlalu jauh dari OB');
    }

    final sl = sweepHigh + slBufferAtr * atrNow;
    final risk = sl - entry;
    if (risk <= 0) return StrategyResult.none(id, name);
    if (risk / entry > maxSlPct) {
      return StrategyResult.none(id, name, note: 'Sweep terlalu dalam (SL >5%)');
    }
    final tp = entry - rr * risk;

    final score = _score(
      choch: true,
      strongBos: strongBos,
      atrHealthy: _atrHealthy(atrNow, price),
      volumeUp: _volumeIncreasing(volumes, dispIdx),
    );
    if (score < minScore) {
      return StrategyResult.none(id, name, note: 'Skor SMC < ambang');
    }

    final vwap = VwapConfig.enabledForSignals
        ? Vwap.confluenceOf(c, TradeDirection.sell, entry)
        : null;
    var conf = score;
    if (vwap != null) {
      conf = vwap.adjust(conf, bonus: 6, penalty: 10, overPenalty: 8);
    }
    final ind = <String, String>{
      'Tren': 'BEARISH (EMA50<EMA200)',
      'Order Block': '${ob.low.toStringAsFixed(4)}–${ob.high.toStringAsFixed(4)}',
      'Liquidity Sweep': sweepHigh.toStringAsFixed(4),
      'CHoCH < ': hlLevel.toStringAsFixed(4),
      'Imbalance(FVG)': gap.toStringAsFixed(4),
      'Entry (limit)': entry.toStringAsFixed(4),
      'Skor SMC': score.toStringAsFixed(0),
      'RR': '1:2,5',
    };
    if (vwap != null && vwap.available) {
      ind['VWAP (target)'] = vwap.vwapValue.toStringAsFixed(4);
    }
    return StrategyResult(
      strategyId: id,
      strategyName: name,
      fired: true,
      direction: TradeDirection.sell,
      confidence: conf,
      entry: entry,
      stopLoss: sl,
      takeProfit: tp,
      indicators: ind,
      note: 'Sweep high → CHoCH bearish → imbalance → sell limit di OB',
    );
  }

  // ---------------------------------------------------------------------------
  // Skoring keyakinan (bobot mengikuti spesifikasi, total dinormalkan ≤ 100).
  // ---------------------------------------------------------------------------
  double _score({
    required bool choch,
    required bool strongBos,
    required bool atrHealthy,
    required bool volumeUp,
  }) {
    double s = 0;
    s += 15; // tren searah (dijamin saat fired)
    s += 20; // order block HTF valid
    s += 20; // liquidity sweep
    s += 15; // imbalance kuat
    s += choch ? 15 : 0; // CHoCH valid
    s += strongBos ? 10 : 0; // BOS/displacement kuat
    s += atrHealthy ? 5 : 0; // ATR sehat
    s += volumeUp ? 5 : 0; // volume meningkat
    return s.clamp(0, 100);
  }

  bool _atrHealthy(double atr, double price) {
    if (price <= 0) return false;
    final r = atr / price;
    return r >= 0.003 && r <= 0.08;
  }

  bool _volumeIncreasing(List<double> volumes, int dispIdx) {
    if (dispIdx < 20) return false;
    double sum = 0;
    for (int i = dispIdx - 20; i < dispIdx; i++) {
      sum += volumes[i];
    }
    final avg = sum / 20;
    return avg > 0 && volumes[dispIdx] > avg;
  }
}
