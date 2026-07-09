/// Arah trade.
class TradeDirection {
  static const String buy = 'BUY';
  static const String sell = 'SELL';
  static const String neutral = 'NEUTRAL';
}

/// Hasil evaluasi satu strategi terhadap satu simbol pada satu candle.
///
/// Bila [fired] == false, strategi tidak menemukan setup; nilai harga tidak
/// relevan. Bila [fired] == true, semua level trade terisi.
class StrategyResult {
  final String strategyId;
  final String strategyName;

  /// Apakah strategi menemukan setup valid.
  final bool fired;

  /// BUY / SELL / NEUTRAL.
  final String direction;

  /// Keyakinan sinyal individual strategi ini (0..100), sebelum ditimbang
  /// dengan akurasi historis.
  final double confidence;

  final double entry;
  final double stopLoss;
  final double takeProfit;

  /// Ringkasan indikator kunci untuk ditampilkan di UI detail.
  final Map<String, String> indicators;

  /// Catatan/penjelasan singkat setup.
  final String note;

  const StrategyResult({
    required this.strategyId,
    required this.strategyName,
    required this.fired,
    required this.direction,
    required this.confidence,
    this.entry = 0,
    this.stopLoss = 0,
    this.takeProfit = 0,
    this.indicators = const {},
    this.note = '',
  });

  /// Hasil "tidak ada setup".
  factory StrategyResult.none(String id, String name, {String note = ''}) {
    return StrategyResult(
      strategyId: id,
      strategyName: name,
      fired: false,
      direction: TradeDirection.neutral,
      confidence: 0,
      note: note,
    );
  }

  /// Jarak risiko absolut (entry -> stop loss).
  double get riskDistance => (entry - stopLoss).abs();

  /// Jarak reward absolut (entry -> take profit).
  double get rewardDistance => (takeProfit - entry).abs();

  /// Rasio Risk:Reward (reward / risk). 0 bila risiko nol.
  double get riskReward =>
      riskDistance <= 0 ? 0 : rewardDistance / riskDistance;
}
