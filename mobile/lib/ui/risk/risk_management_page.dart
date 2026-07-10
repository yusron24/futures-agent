import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/format.dart';
import '../../config/theme.dart';
import '../../models/signal.dart';
import '../../state/app_state.dart';
import '../widgets/signal_badge.dart';

/// Halaman Manajemen Risiko: pengguna mengatur modal simulasi & risiko per
/// trade, lalu ukuran posisi tiap sinyal aktif dihitung otomatis dari jarak SL.
class RiskManagementPage extends StatefulWidget {
  const RiskManagementPage({super.key});
  @override
  State<RiskManagementPage> createState() => _RiskManagementPageState();
}

class _RiskManagementPageState extends State<RiskManagementPage> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final riskAmount = s.riskAmount();

    final activeSignals = <Signal>[
      for (final sym in app.symbols)
        if (app.evaluationFor(sym)?.signal case final sig?)
          if (sig.isActionable) sig,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Risiko')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Modal & Risiko (Simulasi)',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Modal simulasi'),
                      const Spacer(),
                      SizedBox(
                        width: 130,
                        child: TextFormField(
                          initialValue: s.simCapital.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                              prefixText: '\$ ', isDense: true),
                          onFieldSubmitted: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null && parsed > 0) {
                              setState(() => s.simCapital = parsed);
                              app.reevaluateAll();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Risiko per trade'),
                      const Spacer(),
                      Text('${s.riskPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Slider(
                    value: s.riskPercent.clamp(0.1, 10),
                    min: 0.1,
                    max: 10,
                    divisions: 99,
                    activeColor: AppColors.primary,
                    label: '${s.riskPercent.toStringAsFixed(1)}%',
                    onChanged: (v) {
                      setState(() => s.riskPercent = v);
                      app.reevaluateAll();
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text('Risiko modal / trade',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                        const Spacer(),
                        Text('\$${riskAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Ukuran Posisi per Sinyal Aktif',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (activeSignals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.neutral),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Belum ada sinyal aktif untuk dihitung.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...activeSignals.map(
              (sig) => _PositionCard(signal: sig, riskAmount: riskAmount),
            ),
          const SizedBox(height: 20),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Ukuran posisi = Risiko modal ÷ jarak Stop Loss. Semua sinyal '
                'memakai RR tetap 1:2,5.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.signal, required this.riskAmount});
  final Signal signal;
  final double riskAmount;

  @override
  Widget build(BuildContext context) {
    final risk = (signal.entry - signal.stopLoss).abs();
    final qty = risk <= 0 ? 0.0 : riskAmount / risk;
    final notional = qty * signal.entry;
    final potentialProfit = riskAmount * signal.riskReward;

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
                Text('R:R ${Fmt.rr(signal.riskReward)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            _row('Entry', Fmt.price(signal.entry)),
            _row('Stop Loss', Fmt.price(signal.stopLoss)),
            _row('Take Profit', Fmt.price(signal.takeProfit)),
            const Divider(height: 18),
            _row('Ukuran posisi', '${qty.toStringAsFixed(4)} unit',
                highlight: true),
            _row('Nilai posisi (notional)', '\$${notional.toStringAsFixed(2)}'),
            _row('Potensi profit (TP)',
                '\$${potentialProfit.toStringAsFixed(2)}',
                color: AppColors.buy),
            _row('Potensi rugi (SL)', '-\$${riskAmount.toStringAsFixed(2)}',
                color: AppColors.sell),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v,
          {bool highlight = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(k,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(v,
                style: TextStyle(
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                    fontSize: highlight ? 15 : 13,
                    color: color ??
                        (highlight
                            ? AppColors.primary
                            : AppColors.textPrimary))),
          ],
        ),
      );
}
