import '../config/app_config.dart';
import '../data/settings_repository.dart';
import '../models/candle.dart';
import '../models/signal.dart';
import 'confidence_calibration.dart';
import 'signal_engine.dart';
import 'signal_stats_source.dart';
import 'trade_cost.dart';
import 'trade_simulator.dart';

/// Sumber statistik in-memory untuk backtest. Meniru PERSIS akuntansi live:
/// shrinkage sample kecil ([ConfidenceCalibration.shrunkAccuracy]) + decay
/// ([AppConfig.calibDecay]) + cooldown — sehingga walk-forward tidak lebih
/// optimistis dari kenyataan.
class InMemoryStats implements SignalStatsSource {
  final Map<String, List<double>> _acc = {}; // id → [wins, losses]
  final Map<String, int> _cooldownUntil = {};

  @override
  double calibratedAccuracy(String strategyId) {
    final a = _acc[strategyId];
    if (a == null) return ConfidenceCalibration.shrunkAccuracy(0, 0);
    return ConfidenceCalibration.shrunkAccuracy(a[0], a[1]);
  }

  @override
  bool inCooldown(String symbol, int nowMs) =>
      nowMs < (_cooldownUntil[symbol] ?? 0);

  void recordOutcome(List<String> strategyIds, bool win) {
    const decay = AppConfig.calibDecay;
    for (final id in strategyIds) {
      final a = _acc[id] ?? [0.0, 0.0];
      _acc[id] = [
        a[0] * decay + (win ? 1 : 0),
        a[1] * decay + (win ? 0 : 1),
      ];
    }
  }

  void setCooldown(String symbol, int untilMs) =>
      _cooldownUntil[symbol] = untilMs;
}

/// Agregat performa (per strategi / per regime). Semua dalam kelipatan-R net.
class BacktestAgg {
  int trades = 0;
  int wins = 0;
  double netR = 0;

  double get winRate => trades == 0 ? 0 : wins / trades * 100;
  double get avgNetR => trades == 0 ? 0 : netR / trades;
}

/// Satu trade hasil backtest.
class BacktestTrade {
  final int timestamp;
  final String direction;
  final List<String> strategies;
  final String regime;
  final double grossR;
  final double costR;
  final double netR;
  final bool win;
  const BacktestTrade({
    required this.timestamp,
    required this.direction,
    required this.strategies,
    required this.regime,
    required this.grossR,
    required this.costR,
    required this.netR,
    required this.win,
  });
}

/// Laporan backtest. Metrik NET (setelah biaya) sebagai utama; gross ditampilkan
/// terpisah sebagai pembanding (tidak dicampur dalam satu angka).
class BacktestReport {
  final String symbol;
  final int totalTrades;
  final int wins;
  final int losses;
  final double grossExpectancyR;
  final double netExpectancyR;
  final double totalCostR;
  final double? netProfitFactor;
  final double maxDrawdownR;
  final List<double> equityCurveR; // kumulatif netR
  final Map<String, BacktestAgg> perStrategy;
  final Map<String, BacktestAgg> perRegime;
  final List<BacktestTrade> trades;

  const BacktestReport({
    required this.symbol,
    required this.totalTrades,
    required this.wins,
    required this.losses,
    required this.grossExpectancyR,
    required this.netExpectancyR,
    required this.totalCostR,
    required this.netProfitFactor,
    required this.maxDrawdownR,
    required this.equityCurveR,
    required this.perStrategy,
    required this.perRegime,
    required this.trades,
  });

  double get winRate => totalTrades == 0 ? 0 : wins / totalTrades * 100;

  static BacktestReport empty(String symbol) => BacktestReport(
        symbol: symbol,
        totalTrades: 0,
        wins: 0,
        losses: 0,
        grossExpectancyR: 0,
        netExpectancyR: 0,
        totalCostR: 0,
        netProfitFactor: null,
        maxDrawdownR: 0,
        equityCurveR: const [0],
        perStrategy: const {},
        perRegime: const {},
        trades: const [],
      );

  static BacktestReport fromTrades(String symbol, List<BacktestTrade> trades) {
    if (trades.isEmpty) return empty(symbol);
    double sumGross = 0, sumNet = 0, sumCost = 0;
    double posR = 0, negR = 0;
    int wins = 0;
    double equity = 0, peak = 0, maxDd = 0;
    final equityCurve = <double>[0];
    final perStrategy = <String, BacktestAgg>{};
    final perRegime = <String, BacktestAgg>{};

    void bump(Map<String, BacktestAgg> m, String k, bool win, double netR) {
      final a = m.putIfAbsent(k, () => BacktestAgg());
      a.trades++;
      if (win) a.wins++;
      a.netR += netR;
    }

    for (final t in trades) {
      sumGross += t.grossR;
      sumNet += t.netR;
      sumCost += t.costR;
      if (t.netR >= 0) {
        posR += t.netR;
      } else {
        negR += -t.netR;
      }
      if (t.win) wins++;
      equity += t.netR;
      equityCurve.add(equity);
      if (equity > peak) peak = equity;
      final dd = peak - equity;
      if (dd > maxDd) maxDd = dd;
      for (final id in t.strategies) {
        bump(perStrategy, id, t.win, t.netR);
      }
      bump(perRegime, t.regime, t.win, t.netR);
    }

    final n = trades.length;
    return BacktestReport(
      symbol: symbol,
      totalTrades: n,
      wins: wins,
      losses: n - wins,
      grossExpectancyR: sumGross / n,
      netExpectancyR: sumNet / n,
      totalCostR: sumCost,
      netProfitFactor: negR <= 0 ? null : posR / negR,
      maxDrawdownR: maxDd,
      equityCurveR: equityCurve,
      perStrategy: perStrategy,
      perRegime: perRegime,
      trades: trades,
    );
  }
}

/// Backtest walk-forward: me-*replay* [SignalEngine] yang SAMA candle demi candle
/// (tanpa lookahead), mensimulasikan TP/SL ke depan, dan mengagregasi net.
class BacktestRunner {
  BacktestRunner._();

  static BacktestReport run({
    required String symbol,
    required List<Candle> candles,
    required SettingsRepository settings,
    bool applyCost = true,
  }) {
    if (candles.length < AppConfig.backtestMinCandles) {
      return BacktestReport.empty(symbol);
    }
    final stats = InMemoryStats();
    final engine = SignalEngine(settings, stats);
    final intervalMs = AppConfig.intervalMs(settings.interval);
    final cooldownMs =
        settings.cooldownEnabled ? settings.cooldownCandles * intervalMs : 0;

    final trades = <BacktestTrade>[];
    final start = AppConfig.backtestWarmupCandles;
    for (int i = start; i < candles.length - 1; i++) {
      // Sinyal HANYA dari candle tertutup [0..i]; waktu acuan = closeTime candle i.
      final window = candles.sublist(0, i + 1);
      final eval = engine.evaluate(symbol, window,
          nowMsOverride: candles[i].closeTime);
      final sig = eval.signal;
      if (!sig.isActionable) continue;

      // Outcome HANYA dari candle ke depan [i+1..] (tanpa lookahead).
      final sim = simulateTradeOutcome(
        isBuy: sig.isBuy,
        stopLoss: sig.stopLoss,
        takeProfit: sig.takeProfit,
        afterTs: candles[i].openTime,
        candles: candles.sublist(i + 1),
      );
      if (sim.outcome == null) continue; // tak selesai sampai ujung data

      final win = sim.outcome == SignalOutcome.tpHit;
      final grossR = win ? sig.riskReward : -1.0;
      final costR = applyCost
          ? TradeCostModel.costInR(entry: sig.entry, stop: sig.stopLoss)
          : 0.0;
      final netR = TradeCostModel.netR(grossR, costR);

      // Perbarui statistik in-memory (mirip live) → akurasi & cooldown berevolusi.
      stats.recordOutcome(sig.triggeredStrategies, win);
      if (cooldownMs > 0) {
        final mult = win ? 0.5 : 1.0;
        stats.setCooldown(symbol, sim.resolvedAt + (cooldownMs * mult).round());
      }

      trades.add(BacktestTrade(
        timestamp: sig.timestamp,
        direction: sig.direction,
        strategies: sig.triggeredStrategies,
        regime: eval.regime?.label ?? '—',
        grossR: grossR,
        costR: costR,
        netR: netR,
        win: win,
      ));
    }
    return BacktestReport.fromTrades(symbol, trades);
  }
}
