import 'package:intl/intl.dart';

/// Utilitas pemformatan angka & waktu untuk UI.
class Fmt {
  Fmt._();

  /// Format harga adaptif: makin kecil harga, makin banyak desimal.
  static String price(double v) {
    if (v == 0) return '0';
    final abs = v.abs();
    if (abs >= 1000) return NumberFormat('#,##0.00').format(v);
    if (abs >= 1) return v.toStringAsFixed(4);
    if (abs >= 0.01) return v.toStringAsFixed(5);
    return v.toStringAsFixed(8);
  }

  static String pct(double v, {int digits = 2}) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}%';

  static String rr(double v) => '1:${v.toStringAsFixed(1)}';

  static String time(DateTime dt) =>
      DateFormat('dd MMM HH:mm').format(dt.toLocal());

  static String timeShort(DateTime dt) =>
      DateFormat('HH:mm').format(dt.toLocal());
}
