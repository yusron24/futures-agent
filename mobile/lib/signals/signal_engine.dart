import '../config/app_config.dart';
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

    // SL terketat (terdekat ke entry): untuk BUY = stop tertinggi; untuk SELL =
    // stop terendah. Bila terlalu ketat (risiko ~0), pakai fallback aman.
    double stop = isBuy
        ? dirResults.map((r) => r.stopLoss).reduce((a, b) => a > b ? a : b)
        : dirResults.map((r) => r.stopLoss).reduce((a, b) => a < b ? a : b);
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

    // RR TETAP 1:2,5 — invariant utama aplikasi: TP dinormalkan ke persis
    // 2,5× jarak risiko dari SL terketat.
    final risk = (entry - stop).abs();
    final target = isBuy
        ? entry + fixedRiskReward * risk
        : entry - fixedRiskReward * risk;

    // Keyakinan = rata-rata tertimbang (akurasi historis × keyakinan individual)
    // dari strategi searah. Bonus kecil bila ≥2 strategi sepakat.
    double weightSum = 0, confWeighted = 0;
    for (final r in dirResults) {
      final acc = _history.baseAccuracy(r.strategyId);
      weightSum += acc;
      confWeighted += acc * r.confidence;
    }
    double confidence = weightSum == 0
        ? dirResults.first.confidence
        : confWeighted / weightSum;
    if (dirResults.length >= 2) confidence = (confidence + 5);
    confidence = confidence.clamp(0, 100);

    // Filter WAJIB: sinyal hanya aktif bila keyakinan ≥ ambang (mis. 70%).
    // Di bawah itu dikembalikan NEUTRAL sehingga tidak tampil / notifikasi /
    // masuk riwayat, namun rincian strategi tetap tersedia untuk halaman Detail.
    if (confidence < AppConfig.minSignalConfidence) {
      return SymbolEvaluation(
        _neutral(
          symbol,
          ts,
          'Keyakinan ${confidence.toStringAsFixed(0)}% < '
              '${AppConfig.minSignalConfidence.toStringAsFixed(0)}% — dilewati',
        ),
        results,
      );
    }

    final note = dirResults.length >= 2
        ? '${dirResults.length} strategi searah (RR 1:2,5)'
        : dirResults.first.note;

    final signal = Signal(
      symbol: symbol,
      direction: isBuy ? TradeDirection.buy : TradeDirection.sell,
      entry: entry,
      stopLoss: stop,
      takeProfit: target,
      confidence: confidence,
      riskReward: fixedRiskReward,
      triggeredStrategies: dirResults.map((r) => r.strategyId).toList(),
      timestamp: ts,
      note: note,
    );
    return SymbolEvaluation(signal, results);
  }

  /// Rasio Risk:Reward tetap untuk setiap sinyal teragregasi (1:2,5).
  static const double fixedRiskReward = 2.5;

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
