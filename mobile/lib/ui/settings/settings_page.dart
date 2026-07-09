import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../data/settings_repository.dart';
import '../../strategies/strategy_registry.dart';
import '../../state/app_state.dart';

/// Halaman Pengaturan: aktif/nonaktif strategi, risiko per trade, notifikasi,
/// suara & getaran, serta pengelolaan simbol.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _soundOptions = ['alert.mp3', 'chime.mp3', 'ping.mp3'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Strategi Scalping'),
          Card(
            child: Column(
              children: [
                for (int i = 0; i < StrategyRegistry.all.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  SwitchListTile(
                    value: s.isStrategyEnabled(StrategyRegistry.all[i].id),
                    onChanged: (v) => app.toggleStrategy(
                        StrategyRegistry.all[i].id, v),
                    title: Text(StrategyRegistry.all[i].name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(StrategyRegistry.all[i].description,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    activeColor: AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Manajemen Risiko (Simulasi)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Modal simulasi'),
                      const Spacer(),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue: s.simCapital.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            prefixText: '\$ ',
                            isDense: true,
                          ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Notifikasi'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: s.notificationsEnabled,
                  onChanged: (v) => setState(() => s.notificationsEnabled = v),
                  title: const Text('Notifikasi sinyal'),
                  subtitle: const Text('Saat candle 1 jam ditutup & sinyal muncul'),
                  activeColor: AppColors.primary,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: s.soundEnabled,
                  onChanged: (v) => setState(() => s.soundEnabled = v),
                  title: const Text('Suara'),
                  activeColor: AppColors.primary,
                ),
                if (s.soundEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _soundOptions.contains(s.soundName)
                          ? s.soundName
                          : _soundOptions.first,
                      decoration: const InputDecoration(
                          labelText: 'Suara notifikasi', isDense: true),
                      items: _soundOptions
                          .map((o) => DropdownMenuItem(
                              value: o, child: Text(o.split('.').first)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => s.soundName = v ?? s.soundName),
                    ),
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  value: s.vibrationEnabled,
                  onChanged: (v) => setState(() => s.vibrationEnabled = v),
                  title: const Text('Getaran'),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Simbol Dipantau'),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  value: SettingsRepository.modeTopVolume,
                  groupValue: s.symbolMode,
                  onChanged: (v) => app.setSymbolMode(v!),
                  activeColor: AppColors.primary,
                  title: Text('Top ${s.topPairsCount} volume (seluruh Binance)'),
                  subtitle: const Text(
                      'Otomatis memantau pair USDT dengan volume 24 jam tertinggi'),
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: SettingsRepository.modeCustom,
                  groupValue: s.symbolMode,
                  onChanged: (v) => app.setSymbolMode(v!),
                  activeColor: AppColors.primary,
                  title: const Text('Daftar kustom'),
                  subtitle: const Text('Pilih sendiri pair yang dipantau'),
                ),
              ],
            ),
          ),
          if (s.useTopVolume)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Jumlah pair'),
                        const Spacer(),
                        Text('${s.topPairsCount}',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Slider(
                      value: s.topPairsCount.clamp(10, 200).toDouble(),
                      min: 10,
                      max: 200,
                      divisions: 19,
                      activeColor: AppColors.primary,
                      label: '${s.topPairsCount}',
                      onChanged: (v) =>
                          setState(() => s.topPairsCount = v.round()),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Memantau ${app.monitoredCount} pair',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: app.isResolvingSymbols
                              ? null
                              : () => app.refreshTopSymbols(),
                          icon: app.isResolvingSymbols
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.refresh, size: 18),
                          label: const Text('Perbarui'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: s.symbols
                          .map((sym) => Chip(
                                label: Text(sym.replaceAll('USDT', '')),
                                backgroundColor: AppColors.surfaceAlt,
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: s.symbols.length <= 1
                                    ? null
                                    : () => _removeSymbol(app, sym),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: AppConfig.defaultSymbols
                          .where((sym) => !s.symbols.contains(sym))
                          .map((sym) => ActionChip(
                                label: Text('+ ${sym.replaceAll('USDT', '')}'),
                                onPressed: () => _addSymbol(app, sym),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          _sectionTitle('Pembaruan Aplikasi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.system_update,
                          color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Perbarui ke versi terbaru',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('Versi terpasang ${AppConfig.appVersion}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: () => _updateApp(),
                      icon: const Icon(Icons.download),
                      label: const Text('Unduh & pasang APK terbaru'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _openUrl(AppConfig.releasePageUrl),
                      child: const Text('Buka halaman rilis'),
                    ),
                  ),
                  const Text(
                    'Sekali klik: APK terbaru diunduh dari GitHub Releases, '
                    'lalu ketuk berkas untuk memasang (izinkan "Install '
                    'unknown apps" bila diminta).',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Data: Binance · via proxy ${AppConfig.proxyHost}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Buka tautan APK terbaru (unduhan langsung) di aplikasi eksternal/browser.
  Future<void> _updateApp() async {
    final ok = await _openUrl(AppConfig.latestApkUrl);
    if (!ok && mounted) {
      // Fallback ke halaman rilis bila unduhan langsung gagal dibuka.
      await _openUrl(AppConfig.releasePageUrl);
    }
  }

  Future<bool> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka tautan pembaruan')),
        );
      }
      return ok;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka tautan pembaruan')),
        );
      }
      return false;
    }
  }

  void _addSymbol(AppState app, String sym) {
    final list = [...app.settings.symbols, sym];
    app.updateSymbols(list);
  }

  void _removeSymbol(AppState app, String sym) {
    final list = app.settings.symbols.where((e) => e != sym).toList();
    app.updateSymbols(list);
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );
}
