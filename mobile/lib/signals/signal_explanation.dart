import '../models/strategy_result.dart';
import '../strategies/strategy.dart';
import '../strategies/strategy_registry.dart';
import 'market_regime.dart';
import 'signal_engine.dart';
import 'trade_structure.dart';

/// Polaritas sebuah faktor penjelasan (menguatkan / melemahkan / netral).
enum FactorPolarity { positive, negative, neutral }

/// Satu faktor yang menjelaskan keputusan sinyal.
class ExplanationFactor {
  final String label;
  final String detail;
  final FactorPolarity polarity;
  const ExplanationFactor(this.label, this.detail, this.polarity);
}

/// Penjelasan terstruktur satu evaluasi: MENGAPA arah/keyakinan ini terbentuk,
/// atau mengapa sinyal ditahan. Murni (mudah diuji); merangkai data yang sudah
/// ada di [SymbolEvaluation] (reason/regime/results/structure) tanpa hitung ulang.
class SignalExplanation {
  final String headline;
  final bool isActionable;
  final List<ExplanationFactor> factors;
  const SignalExplanation(this.headline, this.isActionable, this.factors);

  static String _tierLabel(StrategyTier t) {
    switch (t) {
      case StrategyTier.core:
        return 'inti';
      case StrategyTier.secondary:
        return 'pendukung';
      case StrategyTier.experimental:
        return 'observasi';
    }
  }

  static FactorPolarity _sevPolarity(StructureSeverity s) {
    switch (s) {
      case StructureSeverity.warn:
      case StructureSeverity.violation:
        return FactorPolarity.negative;
      case StructureSeverity.ok:
      case StructureSeverity.info:
        return FactorPolarity.neutral;
    }
  }

  static ExplanationFactor _regimeFactor(RegimeState reg, String direction) {
    switch (reg.regime) {
      case MarketRegime.trendingUp:
      case MarketRegime.trendingDown:
        final aligned = (reg.regime == MarketRegime.trendingUp &&
                direction == TradeDirection.buy) ||
            (reg.regime == MarketRegime.trendingDown &&
                direction == TradeDirection.sell);
        return ExplanationFactor(
          'Regime ${reg.label}',
          aligned ? 'searah tren → menguatkan' : 'lawan tren → melemahkan',
          aligned ? FactorPolarity.positive : FactorPolarity.negative,
        );
      case MarketRegime.ranging:
        return ExplanationFactor('Regime ${reg.label}',
            'pasar sideways → hati-hati', FactorPolarity.neutral);
      case MarketRegime.transitional:
      case MarketRegime.volatile:
        return ExplanationFactor(
            'Regime ${reg.label}', 'regime belum jelas', FactorPolarity.neutral);
    }
  }

  static SignalExplanation build(SymbolEvaluation eval) {
    final signal = eval.signal;
    final factors = <ExplanationFactor>[];
    final fired = eval.results.where((r) => r.fired).toList();

    if (!signal.isActionable) {
      // Sinyal ditahan / tak ada setup — jelaskan gate penahannya.
      if (fired.isNotEmpty) {
        factors.add(ExplanationFactor(
            'Strategi sempat menyala',
            fired.map((r) => r.strategyName).join(', '),
            FactorPolarity.neutral));
      }
      if (eval.regime != null) {
        factors.add(ExplanationFactor('Regime ${eval.regime!.label}',
            'kondisi pasar saat evaluasi', FactorPolarity.neutral));
      }
      return SignalExplanation(
          'Tidak ada sinyal aktif — ${eval.reason.label}', false, factors);
    }

    final dir = signal.direction;
    // 1) Strategi searah (kontribusi).
    for (final r in fired.where((r) => r.direction == dir)) {
      final s = StrategyRegistry.byId(r.strategyId);
      final tier = s != null ? ' · ${_tierLabel(s.tier)}' : '';
      factors.add(ExplanationFactor(
        r.strategyName,
        'searah, keyakinan ${r.confidence.toStringAsFixed(0)}%$tier',
        FactorPolarity.positive,
      ));
    }
    // 2) Strategi berlawanan (melemahkan).
    for (final r in fired.where((r) =>
        r.direction != dir &&
        (r.direction == TradeDirection.buy ||
            r.direction == TradeDirection.sell))) {
      factors.add(ExplanationFactor(r.strategyName,
          'berlawanan arah → melemahkan keyakinan', FactorPolarity.negative));
    }
    // 3) Regime.
    if (eval.regime != null) factors.add(_regimeFactor(eval.regime!, dir));
    // 4) Struktur TP/SL.
    if (eval.structure != null) {
      for (final f in eval.structure!.findings) {
        factors.add(
            ExplanationFactor('Struktur', f.message, _sevPolarity(f.severity)));
      }
    }
    // 5) RR invariant.
    factors.add(const ExplanationFactor(
        'Risk:Reward', '1:2,5 (TP = 2,5× jarak risiko)', FactorPolarity.neutral));

    final label = dir == TradeDirection.buy ? 'BELI' : 'JUAL';
    return SignalExplanation(
      '$label · keyakinan ${signal.confidence.toStringAsFixed(0)}%',
      true,
      factors,
    );
  }
}
