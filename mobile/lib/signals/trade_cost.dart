import '../config/app_config.dart';

/// Model biaya transaksi (fee + slippage) yang mengubah P/L teoretis menjadi
/// lebih realistis. Semua dinyatakan dalam **kelipatan-R** agar konsisten dengan
/// akuntansi sistem (TP = +riskReward R, SL = −1 R).
///
/// Ide: biaya round-trip dalam fraksi harga = `2·fee + slippage` (masuk + keluar
/// + slippage). Karena 1 R = jarak risiko `|entry − stop|`, biaya dalam R =
/// biaya-fraksi-harga ÷ (jarak-risiko ÷ entry). Jadi makin ketat SL (risk%
/// kecil), makin besar ongkos relatif terhadap R — sesuai kenyataan.
class TradeCostModel {
  TradeCostModel._();

  /// Biaya round-trip dalam kelipatan-R untuk sebuah trade. Mengembalikan 0 bila
  /// input tak valid (risk ≤ 0).
  static double costInR({
    required double entry,
    required double stop,
    double? feePctPerSide,
    double? slippagePct,
  }) {
    final fee = (feePctPerSide ?? AppConfig.tradeFeePctPerSide) / 100.0;
    final slip = (slippagePct ?? AppConfig.tradeSlippagePct) / 100.0;
    final riskDist = (entry - stop).abs();
    if (entry <= 0 || riskDist <= 0) return 0;
    final riskFrac = riskDist / entry; // 1 R sebagai fraksi harga
    final roundTripFrac = 2 * fee + slip; // masuk + keluar + slippage
    return roundTripFrac / riskFrac;
  }

  /// P/L bersih (R) setelah biaya. [grossR] = +riskReward (TP) / −1 (SL).
  static double netR(double grossR, double costR) => grossR - costR;
}
