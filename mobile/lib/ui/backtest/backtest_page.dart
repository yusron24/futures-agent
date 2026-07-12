import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../signals/backtest_engine.dart';
import '../../state/app_state.dart';

/// Halaman Backtest walk-forward: pilih simbol, jalankan replay engine atas
/// candle tersimpan, tampilkan metrik NET (setelah biaya) + atribusi.
class BacktestPage extends StatefulWidget {
  const BacktestPage({super.key});
  @override
  State<BacktestPage> createState() => _BacktestPageState();
}

class _BacktestPageState extends State<BacktestPage> {
  String? _symbol;
  BacktestReport? _report;
  bool _running = false;

  Future<void> _run(AppState app) async {
    final symbol = _symbol ?? (app.symbols.isNotEmpty ? app.symbols.first : null);
    if (symbol == null) return;
    setState(() => _running = true);
    // Beri kesempatan frame render sebelum komputasi sinkron.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final report = app.runBacktest(symbol);
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final symbols = app.symbols;
    _symbol ??= symbols.isNotEmpty ? symbols.first : null;
    final r = _report;

    return Scaffold(
      appBar: AppBar(title: const Text('Backtest (walk-forward)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _symbol,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.surfaceAlt,
                    items: [
                      for (final s in symbols)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _symbol = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _running ? null : () => _run(app),
                child: _running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Jalankan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Replay engine yang sama candle-per-candle atas candle tersimpan. '
            'Metrik di bawah adalah NET (setelah fee + slippage).',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (r == null)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text('Belum ada hasil. Pilih simbol lalu Jalankan.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else if (r.totalTrades == 0)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                    'Tidak ada trade (candle kurang / tak ada setup lolos ambang).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ..._results(r),
        ],
      ),
    );
  }

  List<Widget> _results(BacktestReport r) {
    final pf = r.netProfitFactor;
    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _tile('Trade', '${r.totalTrades}', AppColors.textPrimary),
          _tile('Win rate', '${r.winRate.toStringAsFixed(0)}%', AppColors.primary),
          _tile('PF net', pf == null ? '∞' : pf.toStringAsFixed(2),
              AppColors.warning),
          _tile('Expektansi net',
              '${r.netExpectancyR.toStringAsFixed(2)}R', AppColors.buy),
          _tile('Expektansi gross',
              '${r.grossExpectancyR.toStringAsFixed(2)}R',
              AppColors.textSecondary),
          _tile('Max DD', '${r.maxDrawdownR.toStringAsFixed(1)}R',
              AppColors.sell),
          _tile('Total biaya', '${r.totalCostR.toStringAsFixed(1)}R',
              AppColors.textSecondary),
        ],
      ),
      const SizedBox(height: 20),
      const Text('Equity (kumulatif R net)',
          style: TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      SizedBox(
        height: 120,
        child: CustomPaint(
          painter: _EquityPainter(r.equityCurveR),
          size: const Size(double.infinity, 120),
        ),
      ),
      const SizedBox(height: 20),
      _aggTable('Per Strategi', r.perStrategy),
      const SizedBox(height: 16),
      _aggTable('Per Regime', r.perRegime),
    ];
  }

  Widget _tile(String label, String value, Color color) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );

  Widget _aggTable(String title, Map<String, BacktestAgg> data) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.netR.compareTo(a.value.netR));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(color: AppColors.textPrimary))),
                Text('${e.value.trades} trade · ',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${e.value.winRate.toStringAsFixed(0)}% · ',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${e.value.netR.toStringAsFixed(1)}R',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: e.value.netR >= 0
                            ? AppColors.buy
                            : AppColors.sell)),
              ],
            ),
          ),
      ],
    );
  }
}

class _EquityPainter extends CustomPainter {
  _EquityPainter(this.curve);
  final List<double> curve;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 2) return;
    double min = curve.first, max = curve.first;
    for (final v in curve) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = (max - min).abs() < 1e-9 ? 1.0 : (max - min);
    final dx = size.width / (curve.length - 1);
    double y(double v) => size.height - ((v - min) / range) * size.height;

    // garis nol (jika di dalam rentang)
    if (min < 0 && max > 0) {
      final zeroP = Paint()
        ..color = AppColors.textSecondary.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      final yz = y(0);
      canvas.drawLine(Offset(0, yz), Offset(size.width, yz), zeroP);
    }

    final path = Path()..moveTo(0, y(curve.first));
    for (int i = 1; i < curve.length; i++) {
      path.lineTo(dx * i, y(curve[i]));
    }
    final up = curve.last >= curve.first;
    final line = Paint()
      ..color = up ? AppColors.buy : AppColors.sell
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _EquityPainter old) => old.curve != curve;
}
