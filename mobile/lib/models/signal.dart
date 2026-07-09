import 'package:hive/hive.dart';

part 'signal.g.dart';

/// Status hasil sebuah sinyal setelah dievaluasi terhadap harga berikutnya.
class SignalOutcome {
  static const String pending = 'PENDING';
  static const String tpHit = 'TP_HIT';
  static const String slHit = 'SL_HIT';
  static const String expired = 'EXPIRED';
}

/// Sinyal teragregasi final yang ditampilkan di UI dan disimpan ke riwayat.
@HiveType(typeId: 2)
class Signal {
  @HiveField(0)
  final String symbol;
  @HiveField(1)
  final String direction; // BUY / SELL / NEUTRAL
  @HiveField(2)
  final double entry;
  @HiveField(3)
  final double stopLoss;
  @HiveField(4)
  final double takeProfit;

  /// Keyakinan teragregasi 0..100.
  @HiveField(5)
  final double confidence;

  /// Rasio Risk:Reward.
  @HiveField(6)
  final double riskReward;

  /// ID strategi yang dipicu.
  @HiveField(7)
  final List<String> triggeredStrategies;

  /// Waktu candle penutup pemicu (epoch ms).
  @HiveField(8)
  final int timestamp;

  /// Catatan agregasi (mis. konflik strategi).
  @HiveField(9)
  final String note;

  /// Status hasil (untuk riwayat & statistik akurasi).
  @HiveField(10)
  final String outcome;

  /// Waktu outcome tercapai (epoch ms), 0 bila belum.
  @HiveField(11)
  final int resolvedAt;

  const Signal({
    required this.symbol,
    required this.direction,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.confidence,
    required this.riskReward,
    required this.triggeredStrategies,
    required this.timestamp,
    this.note = '',
    this.outcome = SignalOutcome.pending,
    this.resolvedAt = 0,
  });

  bool get isActionable =>
      direction == 'BUY' || direction == 'SELL';

  bool get isBuy => direction == 'BUY';

  Signal copyWith({String? outcome, int? resolvedAt}) => Signal(
        symbol: symbol,
        direction: direction,
        entry: entry,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        confidence: confidence,
        riskReward: riskReward,
        triggeredStrategies: triggeredStrategies,
        timestamp: timestamp,
        note: note,
        outcome: outcome ?? this.outcome,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );

  DateTime get time =>
      DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);

  /// Kunci unik untuk deduplikasi (satu sinyal per simbol per candle).
  String get key => '$symbol-$timestamp';
}
