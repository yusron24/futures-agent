import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../services/pipeline_metrics.dart';
import '../../services/system_health.dart';
import '../../signals/signal_engine.dart';
import '../../state/app_state.dart';
import '../../strategies/strategy_registry.dart';

/// Halaman Diagnostik (Fase 5): versi, kesehatan sistem, metrik alur sinyal
/// (kenapa sinyal muncul/ditahan), dan akurasi per strategi. Read-only.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final intervalMs = AppConfig.intervalMs(app.settings.interval);
    final health = SystemHealth.instance;
    final status = health.status(intervalMs: intervalMs);
    final snap = PipelineMetrics.instance.snapshot();

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostik & Versi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Versi'),
          _kv('Versi aplikasi', AppConfig.appVersion),
          _kv('Versi skema sinyal', '${AppConfig.signalSchemaVersion}'),
          _kv('Skema tersimpan', '${app.settings.storedSchemaVersion}'),
          _kv('Timeframe', AppConfig.intervalLabel(app.settings.interval)),
          const SizedBox(height: 20),
          _section('Kesehatan Sistem'),
          _kv('Status', _statusLabel(status),
              color: _statusColor(status)),
          _kv('Alasan', health.reason(intervalMs: intervalMs)),
          _kv('Sinyal ditahan (mode aman)',
              health.signalsHeld(intervalMs: intervalMs) ? 'Ya' : 'Tidak'),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _section('Metrik Alur Sinyal')),
              TextButton.icon(
                onPressed: () {
                  PipelineMetrics.instance.reset();
                  setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset'),
              ),
            ],
          ),
          _kv('Total evaluasi', '${snap.totalEvaluations}'),
          _kv('Sinyal aktif', '${snap.actionable}', color: AppColors.buy),
          _kv('Ditahan/kosong', '${snap.held}', color: AppColors.textSecondary),
          const SizedBox(height: 6),
          for (final r in EvalReason.values)
            if (snap.count(r) > 0)
              _kv('· ${r.label}', '${snap.count(r)}',
                  color: r.isHeld
                      ? AppColors.textSecondary
                      : AppColors.buy),
          const SizedBox(height: 20),
          _section('Akurasi per Strategi'),
          for (final s in StrategyRegistry.all) _accuracyRow(app, s.id, s.name),
        ],
      ),
    );
  }

  Widget _accuracyRow(AppState app, String id, String name) {
    final acc = app.history.accuracyOf(id);
    final total = acc.total;
    final rate = (acc.rate * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: const TextStyle(color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis),
          ),
          Text(
            total <= 0
                ? 'belum ada data'
                : '$rate% · ${acc.wins.toStringAsFixed(1)}W/'
                    '${acc.losses.toStringAsFixed(1)}L',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      );

  Widget _kv(String key, String value, {Color color = AppColors.textPrimary}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(key,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  String _statusLabel(HealthStatus s) {
    switch (s) {
      case HealthStatus.healthy:
        return 'Sehat';
      case HealthStatus.degraded:
        return 'Menurun';
      case HealthStatus.tripped:
        return 'Terputus (mode aman)';
    }
  }

  Color _statusColor(HealthStatus s) {
    switch (s) {
      case HealthStatus.healthy:
        return AppColors.buy;
      case HealthStatus.degraded:
        return AppColors.warning;
      case HealthStatus.tripped:
        return AppColors.sell;
    }
  }
}
