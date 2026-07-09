import 'package:hive/hive.dart';

part 'candle.g.dart';

/// Sebuah candlestick OHLCV pada timeframe tertentu.
///
/// [openTime]/[closeTime] adalah epoch milidetik sesuai format Binance.
/// [isClosed] menandakan apakah candle sudah final (penting untuk stream kline
/// di mana candle berjalan dikirim berulang sampai ditutup).
@HiveType(typeId: 1)
class Candle {
  @HiveField(0)
  final int openTime;
  @HiveField(1)
  final double open;
  @HiveField(2)
  final double high;
  @HiveField(3)
  final double low;
  @HiveField(4)
  final double close;
  @HiveField(5)
  final double volume;
  @HiveField(6)
  final int closeTime;
  @HiveField(7)
  final bool isClosed;

  const Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.closeTime,
    this.isClosed = true,
  });

  Candle copyWith({bool? isClosed}) => Candle(
        openTime: openTime,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
        closeTime: closeTime,
        isClosed: isClosed ?? this.isClosed,
      );

  /// Parse dari array kline REST Binance:
  /// [openTime, open, high, low, close, volume, closeTime, ...]
  factory Candle.fromRestArray(List<dynamic> k) {
    return Candle(
      openTime: (k[0] as num).toInt(),
      open: double.parse(k[1].toString()),
      high: double.parse(k[2].toString()),
      low: double.parse(k[3].toString()),
      close: double.parse(k[4].toString()),
      volume: double.parse(k[5].toString()),
      closeTime: (k[6] as num).toInt(),
      isClosed: true,
    );
  }

  /// Parse dari payload stream kline WebSocket (`data['k']`).
  factory Candle.fromWsKline(Map<String, dynamic> k) {
    return Candle(
      openTime: (k['t'] as num).toInt(),
      open: double.parse(k['o'].toString()),
      high: double.parse(k['h'].toString()),
      low: double.parse(k['l'].toString()),
      close: double.parse(k['c'].toString()),
      volume: double.parse(k['v'].toString()),
      closeTime: (k['T'] as num).toInt(),
      isClosed: k['x'] == true,
    );
  }

  DateTime get openDateTime =>
      DateTime.fromMillisecondsSinceEpoch(openTime, isUtc: true);

  @override
  String toString() =>
      'Candle(${openDateTime.toIso8601String()} O:$open H:$high L:$low C:$close V:$volume closed:$isClosed)';
}
