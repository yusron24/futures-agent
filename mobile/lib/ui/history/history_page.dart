import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/format.dart';
import '../../config/theme.dart';
import '../../models/signal.dart';
import '../../state/app_state.dart';
import '../widgets/signal_badge.dart';

/// Halaman Riwayat Sinyal: log yang dapat difilter + statistik akurasi.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _filter = 'ALL'; // ALL / BUY / SELL / TP / SL / PENDING

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final stats = app.history.stats();
    final all = app.history.all();
    final filtered = all.where(_matches).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Sinyal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Bersihkan riwayat',
            onPressed: all.isEmpty ? null : () => _confirmClear(app),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _stat('Total', '${stats.total}', AppColors.textPrimary),
                _stat('Win rate', '${stats.winRate.toStringAsFixed(0)}%',
                    AppColors.primary),
                _stat('TP', '${stats.tp}', AppColors.buy),
                _stat('SL', '${stats.sl}', AppColors.sell),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in ['ALL', 'BUY', 'SELL', 'TP', 'SL', 'PENDING'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      selectedColor: AppColors.primaryDim,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Belum ada sinyal',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _HistoryTile(signal: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  bool _matches(Signal s) {
    switch (_filter) {
      case 'BUY':
        return s.direction == 'BUY';
      case 'SELL':
        return s.direction == 'SELL';
      case 'TP':
        return s.outcome == SignalOutcome.tpHit;
      case 'SL':
        return s.outcome == SignalOutcome.slHit;
      case 'PENDING':
        return s.outcome == SignalOutcome.pending;
      default:
        return true;
    }
  }

  void _confirmClear(AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Bersihkan riwayat?'),
        content: const Text('Semua sinyal tersimpan akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus',
                  style: TextStyle(color: AppColors.sell))),
        ],
      ),
    );
    if (ok == true) {
      await app.history.clear();
      setState(() {});
    }
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.signal});
  final Signal signal;

  Color get _outcomeColor {
    switch (signal.outcome) {
      case SignalOutcome.tpHit:
        return AppColors.buy;
      case SignalOutcome.slHit:
        return AppColors.sell;
      default:
        return AppColors.neutral;
    }
  }

  String get _outcomeLabel {
    switch (signal.outcome) {
      case SignalOutcome.tpHit:
        return 'TP ✓';
      case SignalOutcome.slHit:
        return 'SL ✕';
      default:
        return 'PENDING';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SignalBadge(direction: signal.direction, compact: true),
                const SizedBox(width: 8),
                Text(signal.symbol.replaceAll('USDT', ''),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _outcomeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_outcomeLabel,
                      style: TextStyle(
                          color: _outcomeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _kv('Entry', Fmt.price(signal.entry)),
                _kv('SL', Fmt.price(signal.stopLoss)),
                _kv('TP', Fmt.price(signal.takeProfit)),
                _kv('R:R', Fmt.rr(signal.riskReward)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(Fmt.time(signal.time),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const Spacer(),
                Text('${signal.confidence.toStringAsFixed(0)}% · ${signal.triggeredStrategies.length} strat',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
            Text(v,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      );
}
