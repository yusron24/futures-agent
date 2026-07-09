/// Ringkasan harga realtime satu simbol untuk dashboard.
class SymbolTicker {
  final String symbol;
  final double lastPrice;

  /// Perubahan harga 24 jam dalam persen.
  final double changePercent24h;
  final int updatedAt;

  const SymbolTicker({
    required this.symbol,
    required this.lastPrice,
    required this.changePercent24h,
    required this.updatedAt,
  });

  SymbolTicker copyWith({
    double? lastPrice,
    double? changePercent24h,
    int? updatedAt,
  }) =>
      SymbolTicker(
        symbol: symbol,
        lastPrice: lastPrice ?? this.lastPrice,
        changePercent24h: changePercent24h ?? this.changePercent24h,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Parse dari REST /api/v3/ticker/24hr (mendukung FULL maupun `type=MINI`).
  factory SymbolTicker.fromRest24h(Map<String, dynamic> j) {
    final last = double.parse(j['lastPrice'].toString());
    // `type=MINI` tidak menyertakan priceChangePercent -> hitung dari openPrice.
    double change;
    final pctRaw = j['priceChangePercent'];
    if (pctRaw != null) {
      change = double.tryParse(pctRaw.toString()) ?? 0;
    } else {
      final open = double.tryParse(j['openPrice']?.toString() ?? '') ?? last;
      change = open == 0 ? 0 : ((last - open) / open) * 100;
    }
    return SymbolTicker(
      symbol: j['symbol'] as String,
      lastPrice: last,
      changePercent24h: change,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Update dari payload WebSocket `!miniTicker@arr` / `<symbol>@miniTicker`.
  /// miniTicker menyediakan close (`c`) dan open (`o`) 24 jam.
  factory SymbolTicker.fromMiniTicker(Map<String, dynamic> j) {
    final close = double.parse(j['c'].toString());
    final open = double.parse(j['o'].toString());
    final change = open == 0 ? 0.0 : ((close - open) / open) * 100.0;
    return SymbolTicker(
      symbol: j['s'] as String,
      lastPrice: close,
      changePercent24h: change,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
