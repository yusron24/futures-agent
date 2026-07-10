import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/format.dart';
import '../../config/theme.dart';
import '../../models/symbol_ticker.dart';

/// Menampilkan harga realtime satu simbol yang berkedip hijau saat naik / merah
/// saat turun pada tiap tick (seperti Binance). Terikat ke [ValueListenable]
/// per-simbol dari `AppState.priceListenable(...)` sehingga rebuild hanya widget
/// ini — bukan seluruh dashboard.
class LivePrice extends StatefulWidget {
  const LivePrice({
    super.key,
    required this.listenable,
    this.fallback,
    this.priceStyle,
    this.showChange = true,
    this.changeFontSize = 13,
  });

  final ValueListenable<SymbolTicker?> listenable;
  final SymbolTicker? fallback;
  final TextStyle? priceStyle;
  final bool showChange;
  final double changeFontSize;

  @override
  State<LivePrice> createState() => _LivePriceState();
}

class _LivePriceState extends State<LivePrice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;
  SymbolTicker? _ticker;
  double? _prevPrice;
  Color? _flashColor;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0,
    );
    _ticker = widget.listenable.value ?? widget.fallback;
    _prevPrice = _ticker?.lastPrice;
    widget.listenable.addListener(_onValue);
  }

  @override
  void didUpdateWidget(covariant LivePrice old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_onValue);
      widget.listenable.addListener(_onValue);
      _ticker = widget.listenable.value ?? widget.fallback;
      _prevPrice = _ticker?.lastPrice;
    }
  }

  void _onValue() {
    final t = widget.listenable.value;
    if (t == null || !mounted) return;
    final prev = _prevPrice;
    if (prev != null && t.lastPrice != prev) {
      _flashColor = t.lastPrice > prev ? AppColors.buy : AppColors.sell;
      _flash
        ..value = 1.0
        ..animateTo(0.0, curve: Curves.easeOut);
    }
    _prevPrice = t.lastPrice;
    setState(() => _ticker = t);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onValue);
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.priceStyle ??
        const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary);
    final baseColor = baseStyle.color ?? AppColors.textPrimary;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        final t = _ticker;
        final intensity = _flash.value; // 1 (baru tick) -> 0 (memudar)
        final fc = _flashColor;
        final bg = fc == null
            ? Colors.transparent
            : fc.withValues(alpha: 0.22 * intensity);
        final txtColor = fc == null
            ? baseColor
            : Color.lerp(baseColor, fc, intensity) ?? baseColor;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t == null ? '—' : Fmt.price(t.lastPrice),
                style: baseStyle.copyWith(color: txtColor),
              ),
              if (widget.showChange && t != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    Fmt.pct(t.changePercent24h),
                    style: TextStyle(
                      color: t.changePercent24h >= 0
                          ? AppColors.buy
                          : AppColors.sell,
                      fontWeight: FontWeight.w600,
                      fontSize: widget.changeFontSize,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
