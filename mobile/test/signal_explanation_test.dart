import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/models/signal.dart';
import 'package:scalp_signals/models/strategy_result.dart';
import 'package:scalp_signals/signals/market_regime.dart';
import 'package:scalp_signals/signals/signal_engine.dart';
import 'package:scalp_signals/signals/signal_explanation.dart';
import 'package:scalp_signals/signals/trade_structure.dart';

void main() {
  group('SignalExplanation.build', () {
    test('sinyal aktif → faktor searah(+), berlawanan(−), regime, RR', () {
      final signal = Signal(
        symbol: 'BTCUSDT',
        direction: TradeDirection.buy,
        entry: 100,
        stopLoss: 98,
        takeProfit: 105,
        confidence: 78,
        riskReward: 2.5,
        triggeredStrategies: const ['ma_crossover_adx'],
        timestamp: 0,
      );
      final results = const [
        StrategyResult(
            strategyId: 'ma_crossover_adx',
            strategyName: 'MA Crossover',
            fired: true,
            direction: TradeDirection.buy,
            confidence: 80),
        StrategyResult(
            strategyId: 'macd_divergence',
            strategyName: 'MACD Divergence',
            fired: true,
            direction: TradeDirection.sell,
            confidence: 55),
      ];
      final eval = SymbolEvaluation(
        signal,
        results,
        regime: const RegimeState(
            regime: MarketRegime.trendingUp,
            adx: 30,
            atrPct: 0.02,
            plusDi: 30,
            minusDi: 10),
        reason: EvalReason.actionable,
        structure: const StructureReport(
            [StructureFinding(StructureSeverity.ok, 'Jarak SL wajar (2.00%)')]),
      );

      final exp = SignalExplanation.build(eval);
      expect(exp.isActionable, true);
      expect(exp.headline.contains('BELI'), true);
      expect(exp.headline.contains('78'), true);
      // Kontribusi searah (positif) untuk MA.
      expect(
          exp.factors.any((f) =>
              f.polarity == FactorPolarity.positive &&
              f.label.contains('MA')),
          true);
      // Strategi berlawanan (negatif).
      expect(exp.factors.any((f) => f.polarity == FactorPolarity.negative),
          true);
      // Regime searah tren → positif.
      expect(exp.factors.any((f) => f.label.contains('Regime')), true);
      // RR invariant.
      expect(exp.factors.any((f) => f.label == 'Risk:Reward'), true);
    });

    test('sinyal ditahan → headline sesuai EvalReason, tak actionable', () {
      final neutral = Signal(
        symbol: 'BTCUSDT',
        direction: TradeDirection.neutral,
        entry: 0,
        stopLoss: 0,
        takeProfit: 0,
        confidence: 0,
        riskReward: 0,
        triggeredStrategies: const [],
        timestamp: 0,
      );
      final eval = SymbolEvaluation(neutral, const [],
          reason: EvalReason.cooldown);
      final exp = SignalExplanation.build(eval);
      expect(exp.isActionable, false);
      expect(exp.headline.contains('Cooldown'), true);
    });
  });
}
