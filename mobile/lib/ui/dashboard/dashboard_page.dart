import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/format.dart';
import '../../config/theme.dart';
import '../../models/strategy_result.dart';
import '../../network/binance_ws_client.dart';
import '../../state/app_state.dart';
import '../detail/signal_detail_page.dart';
import '../widgets/live_price.dart';
import '../widgets/signal_badge.dart';

/// Dashboard utama: daftar simbol yang dipantau dengan harga, perubahan 24 jam,
/// dan sinyal terbaru + keyakinan.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Swing Signals'),
            Text('Timeframe ${AppConfig.intervalLabel(app.settings.interval)} · RR 1:2,5 · min ${AppConfig.minSignalConfidence.toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          _ConnectionDot(status: app.wsStatus, online: app.isOnline),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.refreshAll,
        color: AppColors.primary,
        child: app.isLoading && app.evaluations.isEmpty
            ? const _LoadingList()
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (app.errorMessage != null)
                    _OfflineBanner(message: app.errorMessage!),
                  ...app.symbols.map((s) => _SymbolCard(symbol: s)),
                ],
              ),
      ),
    );
  }
}

class _SymbolCard extends StatelessWidget {
  const _SymbolCard({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ticker = app.tickerFor(symbol);
    final eval = app.evaluationFor(symbol);
    final signal = eval?.signal;
    final direction = signal?.direction ?? TradeDirection.neutral;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SignalDetailPage(symbol: symbol),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    symbol.replaceAll('USDT', ''),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text('/USDT',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const Spacer(),
                  SignalBadge(direction: direction, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LivePrice(
                    listenable: app.priceListenable(symbol),
                    fallback: ticker,
                    priceStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (signal != null && signal.isActionable)
                    Text(
                      'R:R ${Fmt.rr(signal.riskReward)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              if (signal != null && signal.isActionable) ...[
                const SizedBox(height: 12),
                ConfidenceBar(
                  confidence: signal.confidence,
                  direction: direction,
                ),
                const SizedBox(height: 6),
                Text(
                  signal.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  signal?.note ?? 'Menunggu setup…',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.status, required this.online});
  final WsStatus status;
  final bool online;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    if (!online) {
      color = AppColors.sell;
      label = 'Offline';
    } else if (status == WsStatus.connected) {
      color = AppColors.buy;
      label = 'Live';
    } else if (status == WsStatus.connecting) {
      color = AppColors.warning;
      label = 'Menyambung';
    } else {
      color = AppColors.neutral;
      label = 'Terputus';
    }
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.warning, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        height: 130,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }
}
