import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../models/candle.dart';
import '../models/signal.dart';
import '../models/strategy_result.dart';
import '../strategies/strategy.dart';
import '../strategies/strategy_registry.dart';

/// Hasil evaluasi lengkap satu simbol: sinyal teragregasi + rincian tiap
/// strategi (untuk halaman detail).
class SymbolEvaluation {
  final Signal signal;
  final List<StrategyResult> results; // termasuk yang tidak menyala
  const SymbolEvaluation(this.signal, this.results);

  List<StrategyResult> get firedResults =>
      results.where((r) => r.fired).toList();
}

/// Mesin yang menjalankan strategi aktif, menimbang dengan akurasi historis,
/// dan mengagregasi menjadi satu sinyal final per simbol.
class SignalEngine {
  SignalEngine(this._settings, this._history);

  final SettingsRepository _settings;
  final SignalHistoryRepository _history;

  /// Evaluasi satu simbol pada candle yang sudah ditutup.
  SymbolEvaluation evaluate(String symbol, List<Candle> closedCandles) {
    final enabled = _settings.enabledStrategies.toSet();
    final results = <StrategyResult>[];

    for (final Strategy s in StrategyRegistry.all) {
      if (!enabled.contains(s.id)) continue;
      try {
        results.add(s.evaluate(symbol, closedCandles));
      } catch (_) {
        results.add(StrategyResult.none(s.id, s.name, note: 'Error evaluasi'));
      }
    }

    final fired = results.where((r) => r.fired).toList();
    final ts = closedCandles.isEmpty ? 0 : closedCandles.last.openTime;

    if (fired.isEmpty) {
      return SymbolEvaluation(
        _neutral(symbol, ts, 'Tidak ada setup'),
        results,
      );
    }

    // Bobot tiap sinyal = akurasi historis strategi × keyakinan individual.
    double buyWeight = 0, sellWeight = 0;
    final buyResults = <StrategyResult>[];
    final sellResults = <StrategyResult>[];
    for (final r in fired) {
      final w = _history.baseAccuracy(r.strategyId) * (r.confidence / 100.0);
      if (r.direction == TradeDirection.buy) {
        buyWeight += w;
        buyResults.add(r);
      } else if (r.direction == TradeDirection.sell) {
        sellWeight += w;
        sellResults.add(r);
      }
    }

    // Konflik: kedua arah punya bobot berarti -> NEUTRAL dengan catatan.
    final strong = buyWeight >= sellWeight ? buyWeight : sellWeight;
    final weak = buyWeight >= sellWeight ? sellWeight : buyWeight;
    if (weak > 0 && weak >= strong * 0.5) {
      return SymbolEvaluation(
        _neutral(symbol, ts,
            'Strategi bertentangan (BUY vs SELL) — menunggu kejelasan'),
        results,
      );
    }

    final isBuy = buyWeight > sellWeight;
    final dirResults = isBuy ? buyResults : sellResults;
    final entry = closedCandles.last.close;

    // SL terketat (memaksimalkan R:R): untuk BUY = stop tertinggi (terdekat ke
    // entry dari bawah); untuk SELL = stop terendah (terdekat ke entry dari
    // atas). Namun jika terlalu ketat sehingga risiko ~0, ambil fallback.
    double stop = isBuy
        ? dirResults.map((r) => r.stopLoss).reduce((a, b) => a > b ? a : b)
        : dirResults.map((r) => r.stopLoss).reduce((a, b) => a < b ? a : b);

    // TP terjauh yang masuk akal.
    final target = isBuy
        ? dirResults.map((r) => r.takeProfit).reduce((a, b) => a > b ? a : b)
        : dirResults.map((r) => r.takeProfit).reduce((a, b) => a < b ? a : b);

    // Validasi geometri: pastikan stop di sisi benar terhadap entry.
    if (isBuy && stop >= entry) {
      stop = dirResults
          .map((r) => r.stopLoss)
          .where((s) => s < entry)
          .fold<double>(entry * 0.99, (a, b) => a < b ? a : b);
    }
    if (!isBuy && stop <= entry) {
      stop = dirResults
          .map((r) => r.stopLoss)
          .where((s) => s > entry)
          .fold<double>(entry * 1.01, (a, b) => a > b ? a : b);
    }

    final risk = (entry - stop).abs();
    final reward = (target - entry).abs();
    final rr = risk == 0 ? 0.0 : reward / risk;

    // Keyakinan teragregasi: probabilistic OR dari bobot ternormalisasi,
    // sehingga kesepakatan banyak strategi menaikkan keyakinan.
    double agreement = 1.0;
    for (final r in dirResults) {
      final w =
          _history.baseAccuracy(r.strategyId) * (r.confidence / 100.0);
      agreement *= (1 - w.clamp(0, 0.99));
    }
    double confidence = (1 - agreement) * 100;
    // Bonus kecil bila lebih dari satu strategi searah.
    if (dirResults.length >= 2) confidence = (confidence + 5).clamp(0, 100);
    confidence = confidence.clamp(0, 100);

    final note = dirResults.length >= 2
        ? '${dirResults.length} strategi searah'
        : dirResults.first.note;

    final signal = Signal(
      symbol: symbol,
      direction: isBuy ? TradeDirection.buy : TradeDirection.sell,
      entry: entry,
      stopLoss: stop,
      takeProfit: target,
      confidence: confidence,
      riskReward: rr,
      triggeredStrategies: dirResults.map((r) => r.strategyId).toList(),
      timestamp: ts,
      note: note,
    );
    return SymbolEvaluation(signal, results);
  }

  Signal _neutral(String symbol, int ts, String note) => Signal(
        symbol: symbol,
        direction: TradeDirection.neutral,
        entry: 0,
        stopLoss: 0,
        takeProfit: 0,
        confidence: 0,
        riskReward: 0,
        triggeredStrategies: const [],
        timestamp: ts,
        note: note,
      );
}
