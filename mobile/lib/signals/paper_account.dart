import '../models/signal.dart';
import 'trade_cost.dart';

/// Ringkasan akun kertas (paper trading) berbasis sinyal yang sudah selesai.
/// SEMUA metrik di sini bersifat **net** (setelah biaya) & dalam satuan uang,
/// terpisah tegas dari [HistoryStats] yang gross/R.
class PaperSummary {
  final double startCapital;
  final double balance; // saldo akhir (uang)
  final int trades;
  final int wins;
  final int losses;
  final double netExpectancyR; // rata-rata R net per trade
  final double grossExpectancyR; // rata-rata R kotor (pembanding)
  final double totalCostR; // total biaya (R)
  final double? netProfitFactor; // null bila belum ada rugi
  final double maxDrawdown; // drawdown maksimum (uang)
  final List<double> equityCurve; // saldo kumulatif per trade

  const PaperSummary({
    required this.startCapital,
    required this.balance,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.netExpectancyR,
    required this.grossExpectancyR,
    required this.totalCostR,
    required this.netProfitFactor,
    required this.maxDrawdown,
    required this.equityCurve,
  });

  double get winRate => trades == 0 ? 0 : wins / trades * 100;
  double get netPnl => balance - startCapital;
  double get netPnlPct =>
      startCapital <= 0 ? 0 : (balance - startCapital) / startCapital * 100;

  static PaperSummary empty(double startCapital) => PaperSummary(
        startCapital: startCapital,
        balance: startCapital,
        trades: 0,
        wins: 0,
        losses: 0,
        netExpectancyR: 0,
        grossExpectancyR: 0,
        totalCostR: 0,
        netProfitFactor: null,
        maxDrawdown: 0,
        equityCurve: [startCapital],
      );
}

/// Menghitung performa paper-trading net dari daftar sinyal historis.
class PaperAccount {
  PaperAccount._();

  /// [signals] boleh berisi campuran status; hanya TP/SL yang dihitung, diurut
  /// menaik berdasarkan waktu penyelesaian. [riskAmount] = uang yang
  /// dipertaruhkan per trade (1 R). [applyCost] mengurangi tiap trade dengan
  /// biaya fee+slippage.
  static PaperSummary summarize(
    List<Signal> signals, {
    required double startCapital,
    required double riskAmount,
    bool applyCost = true,
  }) {
    final resolved = signals
        .where((s) =>
            s.outcome == SignalOutcome.tpHit ||
            s.outcome == SignalOutcome.slHit)
        .toList()
      ..sort((a, b) => a.resolvedAt.compareTo(b.resolvedAt));

    if (resolved.isEmpty) return PaperSummary.empty(startCapital);

    double balance = startCapital;
    double peak = startCapital;
    double maxDd = 0;
    double sumNetR = 0, sumGrossR = 0, sumCostR = 0;
    double grossProfitMoney = 0, grossLossMoney = 0;
    int wins = 0, losses = 0;
    final equity = <double>[startCapital];

    for (final s in resolved) {
      final grossR = s.profitLoss; // +riskReward (TP) / −1 (SL)
      final costR = applyCost
          ? TradeCostModel.costInR(entry: s.entry, stop: s.stopLoss)
          : 0.0;
      final netR = TradeCostModel.netR(grossR, costR);
      final pnl = riskAmount * netR;

      balance += pnl;
      equity.add(balance);
      if (balance > peak) peak = balance;
      final dd = peak - balance;
      if (dd > maxDd) maxDd = dd;

      sumGrossR += grossR;
      sumCostR += costR;
      sumNetR += netR;
      if (pnl >= 0) {
        grossProfitMoney += pnl;
      } else {
        grossLossMoney += -pnl;
      }
      if (s.outcome == SignalOutcome.tpHit) {
        wins++;
      } else {
        losses++;
      }
    }

    final n = resolved.length;
    return PaperSummary(
      startCapital: startCapital,
      balance: balance,
      trades: n,
      wins: wins,
      losses: losses,
      netExpectancyR: sumNetR / n,
      grossExpectancyR: sumGrossR / n,
      totalCostR: sumCostR,
      netProfitFactor:
          grossLossMoney <= 0 ? null : grossProfitMoney / grossLossMoney,
      maxDrawdown: maxDd,
      equityCurve: equity,
    );
  }
}
