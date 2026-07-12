import '../indicators/indicators.dart';
import '../models/candle.dart';
import '../models/strategy_result.dart';
import 'strategy.dart';

/// STRATEGI 7 — Fibonacci Deep Retracement + Stochastic Oversold Rebound.
///
/// Setup buy-the-dip pada kelanjutan tren naik:
/// 1. Impuls naik: swing low `L` → swing high `H` (lookback lebar agar bukan
///    fractal kecil).
/// 2. Harga retrace DALAM ke zona Fib 0.618–0.786 (`level = H − f·(H−L)`).
/// 3. WAJIB: Stochastic(14,3,3) oversold + crossover bullish (inti "rebound",
///    mencegah falling knife). Zona Fib = syarat struktur utama.
/// 4. Booster (tidak wajib): volume surge & konfirmasi candle bullish.
/// 5. SL di bawah level 0.786 (invalidasi struktural), TP = RR 1:2,5 (invariant
///    sistem). Level Fib 0.236 & extension = METADATA/target visual.
class FibRetracementStochastic extends Strategy {
  @override
  String get id => 'fib_retracement_stochastic';
  @override
  StrategyTier get tier => StrategyTier.secondary;
  @override
  String get family => 'fib_retrace';
  @override
  String get name => 'Fib Deep Retracement + Stochastic';
  @override
  String get description =>
      'Buy retrace dalam ke zona Fib 0.618–0.786 dgn rebound Stochastic '
      'oversold. RR tetap 1:2,5; Fib 0.236/extension sbg target visual.';
  @override
  int get minCandles => 120;

  static const int swingLR = 5; // lookback swing (bukan fractal sempit)
  static const int recentHighMax = 60; // swing high harus cukup baru
  static const int atrPeriod = 14;
  static const int stochK = 14, stochSmooth = 3, stochD = 3;
  static const double oversold = 20;
  static const double zoneTolFrac = 0.03; // toleransi zona = 3% dari range
  static const double minRangePct = 0.02; // impuls minimal 2% dari harga
  static const double slBufferAtr = 0.4; // buffer SL agar tahan noise
  static const double maxSlPct = 0.15; // guard SL terlalu lebar
  static const double volSurge = 1.2;
  static const double rr = 2.5;

  @override
  StrategyResult evaluate(String symbol, List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult.none(id, name, note: 'Data kurang');
    }
    final atr = Indicators.atr(candles, atrPeriod);
    final stoch = Indicators.stochastic(candles,
        kPeriod: stochK, kSmooth: stochSmooth, dPeriod: stochD);
    final vols = Indicators.volumes(candles);
    final last = candles.length - 1;

    if (atr[last].isNaN ||
        stoch.k[last].isNaN ||
        stoch.k[last - 1].isNaN ||
        stoch.d[last].isNaN ||
        stoch.d[last - 1].isNaN) {
      return StrategyResult.none(id, name);
    }

    // 1) Impuls naik: swing high terbaru + swing low sebelum-nya.
    final highs = Indicators.swingHighs(candles, left: swingLR, right: swingLR);
    final lows = Indicators.swingLows(candles, left: swingLR, right: swingLR);
    if (highs.isEmpty || lows.isEmpty) {
      return StrategyResult.none(id, name, note: 'Struktur swing tak cukup');
    }
    final ih = highs.last;
    if (last - ih > recentHighMax) {
      return StrategyResult.none(id, name, note: 'Swing high tidak baru');
    }
    final lowsBeforeH = lows.where((i) => i < ih).toList();
    if (lowsBeforeH.isEmpty) {
      return StrategyResult.none(id, name, note: 'Tanpa swing low origin');
    }
    final il = lowsBeforeH.last;
    final hi = candles[ih].high;
    final lo = candles[il].low;
    final range = hi - lo;
    final entry = candles[last].close;
    if (range <= 0 || range < entry * minRangePct) {
      return StrategyResult.none(id, name, note: 'Impuls naik terlalu kecil');
    }

    // 2) Level Fib (level = H − f·(H−L)).
    double fib(double f) => hi - f * range;
    final fib236 = fib(0.236);
    final fib382 = fib(0.382);
    final fib500 = fib(0.5);
    final fib618 = fib(0.618);
    final fib786 = fib(0.786);
    final tol = range * zoneTolFrac;

    // Invalidasi: tembus di bawah swing low (retrace gagal) / di atas H.
    if (entry < lo) {
      return StrategyResult.none(id, name,
          note: 'Retrace tembus swing low — invalid');
    }
    if (entry > hi) return StrategyResult.none(id, name);
    // Zona deep retracement 0.618–0.786.
    final inZone = entry <= fib618 + tol && entry >= fib786 - tol;
    if (!inZone) {
      return StrategyResult.none(id, name,
          note: 'Belum di zona Fib 0.618–0.786');
    }

    // 3) WAJIB: Stochastic oversold + crossover bullish (inti rebound).
    final k = stoch.k, d = stoch.d;
    final crossover = k[last] > d[last] && k[last - 1] <= d[last - 1];
    final wasOversold = k[last] < oversold || k[last - 1] < oversold;
    if (!(crossover && wasOversold)) {
      return StrategyResult.none(id, name,
          note: 'Tanpa rebound Stochastic (oversold+crossover)');
    }

    // 5) SL di bawah 0.786 + buffer ATR; TP = RR 1:2,5.
    final sl = fib786 - slBufferAtr * atr[last];
    final risk = entry - sl;
    if (risk <= 0) return StrategyResult.none(id, name);
    if (risk / entry > maxSlPct) {
      return StrategyResult.none(id, name, note: 'SL terlalu lebar (>15%)');
    }
    final tp = entry + rr * risk;

    // 4) Booster confidence (bukan syarat).
    double conf = 58;
    conf += ((oversold - k[last]) / oversold * 12).clamp(0, 12); // oversold dalam
    final depth = fib618 == fib786
        ? 0.0
        : ((fib618 - entry) / (fib618 - fib786)).clamp(0.0, 1.0);
    conf += depth * 8; // makin dalam retrace, makin baik
    double avg20 = 0;
    int cnt = 0;
    for (int i = last - 20; i < last; i++) {
      if (i >= 0) {
        avg20 += vols[i];
        cnt++;
      }
    }
    avg20 = cnt > 0 ? avg20 / cnt : 0;
    final volRatio = avg20 > 0 ? vols[last] / avg20 : 0.0;
    final hasVolSurge = volRatio >= volSurge;
    if (hasVolSurge) conf += 8;
    final bullConfirm = Indicators.isBullishEngulfing(
            candles[last - 1], candles[last]) ||
        Indicators.isBullishPinBar(candles[last]) ||
        (last >= 2 &&
            Indicators.isMorningStar(
                candles[last - 2], candles[last - 1], candles[last]));
    if (bullConfirm) conf += 8;
    conf = conf.clamp(0, 100);

    // Fib extension (target visual di atas H): ext = L + x·range.
    final ext1618 = lo + 1.618 * range;
    final ext2618 = lo + 2.618 * range;
    final ext3618 = lo + 3.618 * range;

    final notes = <String>['Deep Fib retracement + Stochastic rebound'];
    if (hasVolSurge) notes.add('volume surge');
    if (bullConfirm) notes.add('konfirmasi candle bullish');

    return StrategyResult(
      strategyId: id,
      strategyName: name,
      fired: true,
      direction: TradeDirection.buy,
      confidence: conf,
      entry: entry,
      stopLoss: sl,
      takeProfit: tp,
      indicators: {
        'Swing H/L': '${hi.toStringAsFixed(4)} / ${lo.toStringAsFixed(4)}',
        'Zona 0.618/0.786':
            '${fib618.toStringAsFixed(4)} / ${fib786.toStringAsFixed(4)}',
        'Fib 0.382/0.5': '${fib382.toStringAsFixed(4)} / '
            '${fib500.toStringAsFixed(4)}',
        'Target Fib 0.236': fib236.toStringAsFixed(4),
        'Ext 1.618/2.618/3.618': '${ext1618.toStringAsFixed(4)} / '
            '${ext2618.toStringAsFixed(4)} / ${ext3618.toStringAsFixed(4)}',
        'Stoch K/D':
            '${k[last].toStringAsFixed(1)} / ${d[last].toStringAsFixed(1)}',
        'Volume': '${volRatio.toStringAsFixed(2)}× avg20',
        'RR': '1:2,5',
      },
      note: notes.join(' + '),
    );
  }
}
