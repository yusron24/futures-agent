import '../config/app_config.dart';
import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../models/candle.dart';
import '../models/signal.dart';
import '../models/strategy_result.dart';
import '../strategies/strategy.dart';
import '../strategies/strategy_registry.dart';
import 'confidence_calibration.dart';
import 'data_quality.dart';
import 'market_regime.dart';

/// Hasil evaluasi lengkap satu simbol: sinyal teragregasi + rincian tiap
/// strategi (untuk halaman detail).
class SymbolEvaluation {
  final Signal signal;
  final List<StrategyResult> results; // termasuk yang tidak menyala
  final RegimeState? regime; // snapshot regime pasar (Fase 3), bila dihitung
  const SymbolEvaluation(this.signal, this.results, [this.regime]);

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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final intervalMs = AppConfig.intervalMs(_settings.interval);
    final ts = closedCandles.isEmpty ? 0 : closedCandles.last.openTime;

    // GERBANG MUTU DATA — hentikan lebih awal bila input buruk (candle bolong/
    // duplikat/stale) agar strategi tidak menghasilkan sinyal palsu.
    final dq = DataQualityGate.assess(
      closedCandles,
      intervalMs: intervalMs,
      nowMs: nowMs,
    );
    if (dq.severity == DqSeverity.block && _settings.dataQualityStrict) {
      return SymbolEvaluation(
        _neutral(symbol, ts, 'Mutu data buruk: ${dq.summary}'),
        const [],
      );
    }

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

    if (fired.isEmpty) {
      return SymbolEvaluation(
        _neutral(symbol, ts, 'Tidak ada setup'),
        results,
      );
    }

    // Metadata tier/family per strategi.
    final stratById = {for (final s in StrategyRegistry.all) s.id: s};
    StrategyTier tierOf(String id) =>
        stratById[id]?.tier ?? StrategyTier.secondary;
    String familyOf(String id) => stratById[id]?.family ?? id;
    // Bobot berbobot-akurasi (untuk memilih arah & merata-rata confidence).
    double rawW(StrategyResult r) =>
        ConfidenceCalibration.tierWeight(tierOf(r.strategyId)) *
        _history.calibratedAccuracy(r.strategyId) *
        (r.confidence / 100.0);
    // Bobot STRUKTURAL (tier×conf) untuk evidence kalibrasi — TANPA akurasi.
    double structW(StrategyResult r) =>
        ConfidenceCalibration.tierWeight(tierOf(r.strategyId)) *
        (r.confidence / 100.0);
    double sumRawW(Iterable<StrategyResult> rs) =>
        rs.fold(0.0, (a, r) => a + rawW(r));
    Iterable<StrategyResult> dirOf(Iterable<StrategyResult> rs, String d) =>
        rs.where((r) => r.direction == d);

    final core =
        fired.where((r) => tierOf(r.strategyId) == StrategyTier.core).toList();
    final secondary = fired
        .where((r) => tierOf(r.strategyId) == StrategyTier.secondary)
        .toList();

    // ANCHOR ARAH: CORE menentukan arah. Bila tak ada core → secondary jadi
    // anchor cadangan (dengan penalti). Experimental TIDAK pernah jadi anchor.
    final String anchorDir;
    final bool coreAnchored;
    final coreBuyW = sumRawW(dirOf(core, TradeDirection.buy));
    final coreSellW = sumRawW(dirOf(core, TradeDirection.sell));
    if (coreBuyW > 0 || coreSellW > 0) {
      coreAnchored = true;
      final strong = coreBuyW >= coreSellW ? coreBuyW : coreSellW;
      final weak = coreBuyW >= coreSellW ? coreSellW : coreBuyW;
      if (weak > 0 && weak >= strong * 0.5) {
        return SymbolEvaluation(
          _neutral(symbol, ts, 'Core bertentangan (BUY vs SELL)'),
          results,
        );
      }
      anchorDir =
          coreBuyW >= coreSellW ? TradeDirection.buy : TradeDirection.sell;
    } else {
      final secBuyW = sumRawW(dirOf(secondary, TradeDirection.buy));
      final secSellW = sumRawW(dirOf(secondary, TradeDirection.sell));
      if (secBuyW <= 0 && secSellW <= 0) {
        // Hanya strategi experimental yang menyala → observasi, bukan sinyal.
        return SymbolEvaluation(
          _neutral(symbol, ts,
              'Hanya strategi observasi — menunggu konfirmasi core/secondary'),
          results,
        );
      }
      coreAnchored = false;
      final strong = secBuyW >= secSellW ? secBuyW : secSellW;
      final weak = secBuyW >= secSellW ? secSellW : secBuyW;
      if (weak > 0 && weak >= strong * 0.5) {
        return SymbolEvaluation(
          _neutral(symbol, ts, 'Strategi bertentangan (BUY vs SELL)'),
          results,
        );
      }
      anchorDir =
          secBuyW >= secSellW ? TradeDirection.buy : TradeDirection.sell;
    }

    final isBuy = anchorDir == TradeDirection.buy;
    // Semua hasil searah anchor (core+secondary+experimental) memperkuat.
    final dirResults = fired.where((r) => r.direction == anchorDir).toList();
    final oppResults = fired
        .where((r) =>
            r.direction != anchorDir &&
            (r.direction == TradeDirection.buy ||
                r.direction == TradeDirection.sell))
        .toList();
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

    // CONFIDENCE — dua sumbu terpisah agar sample kecil tak menekan dua kali:
    // (1) confRaw = rata-rata confidence tertimbang bobot efektif (family-diskon,
    //     berbobot-akurasi).
    final effW = ConfidenceCalibration.familyEffectiveWeights(
      dirResults.map((r) => (familyOf(r.strategyId), rawW(r))).toList(),
    );
    double wSum = 0, cw = 0;
    for (int i = 0; i < dirResults.length; i++) {
      wSum += effW[i];
      cw += effW[i] * dirResults[i].confidence;
    }
    final confRaw = wSum > 0 ? cw / wSum : dirResults.first.confidence;
    // (2) evidence = kesepakatan STRUKTURAL (tier×conf, family-diskon) TANPA
    //     akurasi/sample → setup baru-tapi-kuat tetap ber-evidence penuh.
    final evidence = ConfidenceCalibration.familyEffectiveTotal(
      dirResults.map((r) => (familyOf(r.strategyId), structW(r))).toList(),
    );
    double confidence = ConfidenceCalibration.calibrate(confRaw, evidence);

    // Penalti ketidaksepakatan: arah berlawanan MELEMAHKAN (tak membalik).
    final oppW = oppResults.fold<double>(0, (a, r) => a + structW(r));
    if (oppW > 0) {
      confidence -= (oppW * AppConfig.disagreementPenalty).clamp(0, 20);
    }
    // Penalti bila arah hanya di-anchor secondary (tanpa core).
    if (!coreAnchored) confidence -= AppConfig.noCoreAnchorPenalty;
    // Penalti mutu data tingkat "warn".
    if (dq.severity == DqSeverity.warn) confidence -= 5;

    // FILTER REGIME PASAR (Fase 3): SATU modifier confidence + hard-hold khusus
    // chop. TIDAK mengubah arah (arah tetap dari core di atas).
    RegimeState? regime;
    if (_settings.regimeFilterEnabled) {
      regime = MarketRegimeDetector.detect(closedCandles);
      // Hard-hold hanya untuk chop tanpa arah (ATR tinggi ∧ ADX rendah).
      // Directional volatility (tren + ATR tinggi) TIDAK ditahan.
      if (regime.hold) {
        return SymbolEvaluation(
          _neutral(symbol, ts,
              'Regime ${regime.label} (ATR tinggi tanpa arah) — menahan sinyal'),
          results,
          regime,
        );
      }
      confidence += MarketRegimeDetector.confidenceAdjustment(
        regime,
        anchorDir,
        dirResults.map((r) => (familyOf(r.strategyId), structW(r))).toList(),
      );
    }
    confidence = confidence.clamp(0, 100);

    // COOLDOWN: setelah TP/SL simbol ini, tahan sinyal baru beberapa candle
    // (mencegah entry beruntun & notifikasi spam).
    if (_settings.cooldownEnabled && _history.inCooldown(symbol, nowMs)) {
      return SymbolEvaluation(
        _neutral(symbol, ts, 'Cooldown aktif — menahan sinyal baru'),
        results,
        regime,
      );
    }

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
        regime,
      );
    }

    final baseNote = dirResults.length >= 2
        ? '${dirResults.length} strategi searah (RR 1:2,5)'
        : dirResults.first.note;
    final note =
        regime != null ? '$baseNote · Regime: ${regime.label}' : baseNote;

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
    return SymbolEvaluation(signal, results, regime);
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
