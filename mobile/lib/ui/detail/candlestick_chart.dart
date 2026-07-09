import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/candle.dart';
import '../../models/signal.dart';

/// Grafik candlestick 1 jam sederhana namun akurat dengan garis Entry/SL/TP.
/// Digambar dengan [CustomPainter] agar tanpa dependency charting eksternal.
class CandlestickChart extends StatelessWidget {
  const CandlestickChart({
    super.key,
    required this.candles,
    this.signal,
    this.maxCandles = 80,
    this.height = 280,
  });

  final List<Candle> candles;
  final Signal? signal;
  final int maxCandles;
  final double height;

  @override
  Widget build(BuildContext context) {
    final data = candles.length > maxCandles
        ? candles.sublist(candles.length - maxCandles)
        : candles;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CandlePainter(data, signal),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles, this.signal);
  final List<Candle> candles;
  final Signal? signal;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const leftPad = 4.0;
    const rightPad = 62.0; // ruang label harga
    const topPad = 8.0;
    const bottomPad = 8.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    double minP = double.infinity, maxP = -double.infinity;
    for (final c in candles) {
      minP = math.min(minP, c.low);
      maxP = math.max(maxP, c.high);
    }
    // Sertakan level sinyal dalam skala bila ada.
    if (signal != null && signal!.isActionable) {
      for (final v in [signal!.entry, signal!.stopLoss, signal!.takeProfit]) {
        minP = math.min(minP, v);
        maxP = math.max(maxP, v);
      }
    }
    if (maxP <= minP) maxP = minP + 1;
    final range = maxP - minP;
    final pad = range * 0.05;
    minP -= pad;
    maxP += pad;

    double yFor(double price) =>
        topPad + chartH * (1 - (price - minP) / (maxP - minP));

    // Grid horizontal + label harga.
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    const gridLines = 4;
    for (int i = 0; i <= gridLines; i++) {
      final price = minP + (maxP - minP) * i / gridLines;
      final y = yFor(price);
      canvas.drawLine(
          Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
      _drawText(canvas, _fmt(price), Offset(leftPad + chartW + 4, y - 6),
          AppColors.textSecondary, 9);
    }

    // Candles.
    final slot = chartW / candles.length;
    final bodyW = math.max(1.0, slot * 0.6);
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = leftPad + slot * (i + 0.5);
      final isUp = c.close >= c.open;
      final color = isUp ? AppColors.buy : AppColors.sell;
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(cx, yFor(c.high)), Offset(cx, yFor(c.low)), wickPaint);
      final openY = yFor(c.open);
      final closeY = yFor(c.close);
      final top = math.min(openY, closeY);
      final bottom = math.max(openY, closeY);
      final bodyPaint = Paint()..color = color;
      canvas.drawRect(
        Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
            bottom <= top ? top + 1 : bottom),
        bodyPaint,
      );
    }

    // Garis Entry / SL / TP.
    if (signal != null && signal!.isActionable) {
      _drawLevel(canvas, size, yFor(signal!.entry), AppColors.primary, 'ENTRY',
          leftPad, chartW);
      _drawLevel(canvas, size, yFor(signal!.stopLoss), AppColors.sell, 'SL',
          leftPad, chartW);
      _drawLevel(canvas, size, yFor(signal!.takeProfit), AppColors.buy, 'TP',
          leftPad, chartW);
    }
  }

  void _drawLevel(Canvas canvas, Size size, double y, Color color, String label,
      double leftPad, double chartW) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    // Garis putus-putus.
    const dash = 6.0, gap = 4.0;
    double x = leftPad;
    while (x < leftPad + chartW) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
    final tagRect = Rect.fromLTWH(leftPad, y - 7, 40, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, const Radius.circular(3)),
      Paint()..color = color.withValues(alpha: 0.9),
    );
    _drawText(canvas, label, Offset(leftPad + 3, y - 6), Colors.white, 9,
        bold: true);
  }

  void _drawText(Canvas canvas, String text, Offset pos, Color color, double size,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  String _fmt(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles || old.signal != signal;
}
