import 'breakout_key_level_volume.dart';
import 'double_bottom_top.dart';
import 'fib_retracement_stochastic.dart';
import 'liquidity_swap_sniper_entry.dart';
import 'macd_divergence.dart';
import 'ma_crossover_adx.dart';
import 'pullback_ema200_support.dart';
import 'strategy.dart';

/// Daftar tunggal semua strategi swing yang tersedia. Urutan menentukan
/// tampilan di Pengaturan.
class StrategyRegistry {
  StrategyRegistry._();

  static final List<Strategy> all = <Strategy>[
    BreakoutKeyLevelVolume(),
    PullbackEma200Support(),
    MacdDivergence(),
    DoubleBottomTop(),
    MaCrossoverAdx(),
    LiquiditySwapSniperEntry(),
    FibRetracementStochastic(),
  ];

  static Strategy? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static List<String> get allIds => all.map((s) => s.id).toList();
}
