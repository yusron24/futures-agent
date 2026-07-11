import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../indicators/vwap.dart';
import '../../models/candle.dart';
import '../../models/signal.dart';

/// Grafik candlestick sederhana namun akurat dengan garis Entry/SL/TP dan
/// (opsional) VWAP + 3 band. Digambar dengan [CustomPainter] tanpa dependency
/// charting eksternal.
class CandlestickChart extends StatelessWidget {
  const CandlestickChart({
    super.key,
    required this.candles,
    this.signal,
    this.showVwap = false,
    this.maxCandles = 80,
    this.height = 280,
  });

  final List<Candle> candles;
  final Signal? signal;
  final bool showVwap;
  final int maxCandles;
  final double height;

  @override
  Widget build(BuildContext context) {
    final start =
        candles.length > maxCandles ? candles.length - maxCandles : 0;
    final data = candles.sublist(start);

    // Hitung VWAP pada candles PENUH (konsisten dgn strategi/engine), lalu
    // potong ke jendela tampil agar nilai identik.
    VwapResult? vwap;
    if (showVwap && data.isNotEmpty) {
      final full = Vwap.compute(candles);
      vwap = VwapResult(
        full.vwap.sublist(start),
        full.upper1.sublist(start),
        full.upper2.sublist(start),
        full.upper3.sublist(start),
        full.lower1.sublist(start),
        full.lower2.sublist(start),
        full.lower3.sublist(start),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CandlePainter(data, signal, vwap),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles, this.signal, this.vwap);
  final List<Candle> candles;
  final Signal? signal;
  final VwapResult? vwap;

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
    // Sertakan VWAP & band-1 dalam skala (band-2/3 dibiarkan ter-clip).
    final vw = vwap;
    if (vw != null) {
      for (int i = 0; i < candles.length && i < vw.length; i++) {
        for (final v in [vw.vwap[i], vw.upper1[i], vw.lower1[i]]) {
          if (!v.isNaN) {
            minP = math.min(minP, v);
            maxP = math.max(maxP, v);
          }
        }
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

    // VWAP + band (di bawah garis sinyal agar Entry/SL/TP tetap menonjol).
    if (vw != null) {
      final slot = chartW / candles.length;
      double xAt(int i) => leftPad + slot * (i + 0.5);
      final bandColor = AppColors.vwap.withValues(alpha: 0.3);
      _drawSeries(canvas, vw.upper3, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.upper2, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.upper1, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.lower1, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.lower2, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.lower3, xAt, yFor, bandColor, 0.8, dashed: true);
      _drawSeries(canvas, vw.vwap, xAt, yFor, AppColors.vwap, 1.5);
      _drawText(canvas, 'VWAP', Offset(leftPad + 3, topPad + 2),
          AppColors.vwap, 9, bold: true);
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

  /// Gambar deret nilai (mis. VWAP/band) sebagai garis, melompati NaN.
  void _drawSeries(
    Canvas canvas,
    List<double> values,
    double Function(int) xAt,
    double Function(double) yFor,
    Color color,
    double strokeWidth, {
    bool dashed = false,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    Offset? prev;
    for (int i = 0; i < values.length; i++) {
      if (values[i].isNaN) {
        prev = null;
        continue;
      }
      final p = Offset(xAt(i), yFor(values[i]));
      if (prev != null) {
        if (dashed) {
          _dashedLine(canvas, prev, p, paint);
        } else {
          canvas.drawLine(prev, p, paint);
        }
      }
      prev = p;
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0, gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    double drawn = 0;
    while (drawn < total) {
      final segEnd = math.min(drawn + dash, total);
      canvas.drawLine(a + dir * drawn, a + dir * segEnd, paint);
      drawn = segEnd + gap;
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
      old.candles != candles || old.signal != signal || old.vwap != vwap;
}
