import 'bollinger_squeeze_breakout.dart';
import 'ema_pullback_rsi_divergence.dart';
import 'macd_zeroline_engulfing.dart';
import 'stochastic_pinbar_reversal.dart';
import 'strategy.dart';
import 'volume_profile_flip.dart';

/// Daftar tunggal semua strategi yang tersedia. Urutan menentukan tampilan di
/// Pengaturan.
class StrategyRegistry {
  StrategyRegistry._();

  static final List<Strategy> all = <Strategy>[
    EmaPullbackRsiDivergence(),
    BollingerSqueezeBreakout(),
    MacdZeroLineEngulfing(),
    VolumeProfileFlip(),
    StochasticPinBarReversal(),
  ];

  static Strategy? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static List<String> get allIds => all.map((s) => s.id).toList();
}
