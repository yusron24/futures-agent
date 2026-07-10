import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/format.dart';
import '../../config/theme.dart';
import '../../models/strategy_result.dart';
import '../../state/app_state.dart';
import '../widgets/signal_badge.dart';
import 'candlestick_chart.dart';

/// Halaman detail sinyal: chart candlestick 1h dengan garis Entry/SL/TP,
/// level trade, R:R, dan ringkasan tiap strategi.
class SignalDetailPage extends StatelessWidget {
  const SignalDetailPage({super.key, required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eval = app.evaluationFor(symbol);
    final signal = eval?.signal;
    final candles = app.candles.candles(symbol);
    final ticker = app.tickerFor(symbol);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(symbol.replaceAll('USDT', '')),
            const Text('/USDT',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                    fontSize: 16)),
            const Spacer(),
            if (signal != null)
              SignalBadge(direction: signal.direction, compact: true),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ticker != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.price(ticker.lastPrice),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text(Fmt.pct(ticker.changePercent24h),
                    style: TextStyle(
                        color: ticker.changePercent24h >= 0
                            ? AppColors.buy
                            : AppColors.sell,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CandlestickChart(candles: candles, signal: signal),
            ),
          ),
          const SizedBox(height: 16),
          if (signal != null && signal.isActionable) ...[
            _TradePlan(signal: signal, app: app),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.sell,
                  side: BorderSide(
                      color: AppColors.sell.withValues(alpha: 0.5)),
                ),
                onPressed: () => _confirmReset(context, app),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset sinyal'),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_empty,
                        color: AppColors.neutral),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(signal?.note ?? 'Belum ada setup aktif',
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          const Text('Ringkasan Strategi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...?eval?.results.map((r) => _StrategyTile(result: r)),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset sinyal?'),
        content: const Text(
            'Sinyal aktif ini akan diabaikan (tidak ikut statistik) dan hilang '
            'dari dashboard. Simbol tetap dipantau & dapat memunculkan sinyal '
            'baru nanti.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset',
                  style: TextStyle(color: AppColors.sell))),
        ],
      ),
    );
    if (ok == true) {
      await app.ignoreSignal(symbol);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _TradePlan extends StatelessWidget {
  const _TradePlan({required this.signal, required this.app});
  final dynamic signal;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forDirection(signal.direction);
    final risk = (signal.entry - signal.stopLoss).abs();
    final reward = (signal.takeProfit - signal.entry).abs();
    final riskAmount = app.settings.riskAmount();
    final positionSize = risk == 0 ? 0.0 : riskAmount / risk;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SignalBadge(direction: signal.direction),
                const Spacer(),
                Text('R:R ${Fmt.rr(signal.riskReward)}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 14),
            ConfidenceBar(
                confidence: signal.confidence, direction: signal.direction),
            const SizedBox(height: 16),
            _levelRow('Entry', signal.entry, AppColors.primary),
            const Divider(height: 20),
            _levelRow('Stop Loss', signal.stopLoss, AppColors.sell),
            const Divider(height: 20),
            _levelRow('Take Profit', signal.takeProfit, AppColors.buy),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _metaRow('Risiko / unit', Fmt.price(risk)),
                  const SizedBox(height: 6),
                  _metaRow('Reward / unit', Fmt.price(reward)),
                  const SizedBox(height: 6),
                  _metaRow('Ukuran posisi (simulasi)',
                      '${positionSize.toStringAsFixed(4)} unit'),
                  const SizedBox(height: 6),
                  _metaRow('Risiko modal',
                      '\$${riskAmount.toStringAsFixed(2)} (${app.settings.riskPercent.toStringAsFixed(1)}%)'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text('Dipicu oleh: ${signal.triggeredStrategies.length} strategi',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _levelRow(String label, double value, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
        const Spacer(),
        Text(Fmt.price(value),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }

  Widget _metaRow(String k, String v) => Row(
        children: [
          Text(k,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      );
}

class _StrategyTile extends StatelessWidget {
  const _StrategyTile({required this.result});
  final StrategyResult result;

  @override
  Widget build(BuildContext context) {
    final fired = result.fired;
    final color = fired
        ? AppColors.forDirection(result.direction)
        : AppColors.neutral;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          fired ? Icons.check_circle : Icons.remove_circle_outline,
          color: color,
        ),
        title: Text(result.strategyName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          fired
              ? '${result.direction} · ${result.confidence.toStringAsFixed(0)}% · R:R ${Fmt.rr(result.riskReward)}'
              : (result.note.isEmpty ? 'Tidak aktif' : result.note),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(result.note,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ),
                ...result.indicators.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(e.key,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        const Spacer(),
                        Text(e.value,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
