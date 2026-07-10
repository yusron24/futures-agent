import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../models/candle.dart';
import '../models/symbol_ticker.dart';
import 'proxy_http_client.dart';

/// Peristiwa yang dipancarkan oleh [BinanceWsClient].
class WsCandleEvent {
  final String symbol;
  final Candle candle;
  const WsCandleEvent(this.symbol, this.candle);
}

class WsTickerEvent {
  final SymbolTicker ticker;
  const WsTickerEvent(this.ticker);
}

/// Tick harga per-transaksi dari stream `<symbol>@trade`.
class WsTradeEvent {
  final String symbol;
  final double price;
  const WsTradeEvent(this.symbol, this.price);
}

/// Status koneksi WebSocket untuk indikator UI.
enum WsStatus { connecting, connected, disconnected }

/// Klien WebSocket Binance untuk kline 1h + miniTicker banyak simbol,
/// diarahkan melalui proxy HTTP.
///
/// Untuk mendukung **ratusan pair** tanpa URL raksasa, klien terhubung ke
/// endpoint mentah `/ws` lalu mengirim pesan kontrol `SUBSCRIBE` secara
/// berkelompok (batch). Pesan masuk berupa event mentah yang dibedakan lewat
/// field `e` (`kline` / `24hrMiniTicker`).
///
/// Koneksi wss ditunnel via HTTP CONNECT ke proxy dengan menyerahkan
/// [ProxyHttpClient] ke [WebSocket.connect] (`customClient`).
class BinanceWsClient {
  BinanceWsClient(
    this.symbols, {
    this.includeMiniTicker = true,
    this.interval = AppConfig.defaultInterval,
  });

  List<String> symbols;

  /// Bila false, hanya berlangganan stream kline (hemat bandwidth) — harga
  /// live tetap tersedia dari field close kline.
  final bool includeMiniTicker;

  /// Timeframe kline yang di-stream ('1h' / '4h' / '1d').
  final String interval;

  WebSocket? _socket;
  StreamSubscription? _sub;
  HttpClient? _httpClient;
  bool _closedByUser = false;
  int _reconnectAttempt = 0;
  int _msgId = 0;
  Timer? _reconnectTimer;

  final _candleController = StreamController<WsCandleEvent>.broadcast();
  final _tickerController = StreamController<WsTickerEvent>.broadcast();
  final _tradeController = StreamController<WsTradeEvent>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<WsCandleEvent> get candleStream => _candleController.stream;
  Stream<WsTickerEvent> get tickerStream => _tickerController.stream;
  Stream<WsTradeEvent> get tradeStream => _tradeController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;

  /// Daftar nama stream (2 per simbol: kline_1h + miniTicker).
  List<String> _streamsFor(List<String> syms) {
    final streams = <String>[];
    for (final s in syms) {
      final lower = s.toLowerCase();
      streams.add('$lower@kline_$interval');
      if (includeMiniTicker) streams.add('$lower@miniTicker');
    }
    return streams;
  }

  Future<void> connect() async {
    _closedByUser = false;
    await _openConnection();
  }

  Future<void> _openConnection() async {
    _statusController.add(WsStatus.connecting);
    try {
      _httpClient?.close(force: true);
      _httpClient = ProxyHttpClient.create();
      final socket = await WebSocket.connect(
        AppConfig.wsRawUrl,
        customClient: _httpClient,
      ).timeout(const Duration(seconds: 25));

      _socket = socket;
      _reconnectAttempt = 0;
      _statusController.add(WsStatus.connected);

      _sub = socket.listen(
        _onMessage,
        onError: (Object e) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );

      _sendSubscribe(_streamsFor(symbols));
    } catch (_) {
      _handleDisconnect();
    }
  }

  /// Kirim SUBSCRIBE untuk daftar stream, dipecah menjadi batch agar aman.
  void _sendSubscribe(List<String> streams, {int batchSize = 100}) {
    final socket = _socket;
    if (socket == null) return;
    for (var i = 0; i < streams.length; i += batchSize) {
      final chunk = streams.sublist(
          i, i + batchSize > streams.length ? streams.length : i + batchSize);
      socket.add(jsonEncode({
        'method': 'SUBSCRIBE',
        'params': chunk,
        'id': ++_msgId,
      }));
    }
  }

  void _sendUnsubscribe(List<String> streams, {int batchSize = 100}) {
    final socket = _socket;
    if (socket == null) return;
    for (var i = 0; i < streams.length; i += batchSize) {
      final chunk = streams.sublist(
          i, i + batchSize > streams.length ? streams.length : i + batchSize);
      socket.add(jsonEncode({
        'method': 'UNSUBSCRIBE',
        'params': chunk,
        'id': ++_msgId,
      }));
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map<String, dynamic>) return;

      // Balasan kontrol SUBSCRIBE/UNSUBSCRIBE: {"result":null,"id":N}.
      if (decoded.containsKey('result')) return;

      // Event mentah dari /ws dibedakan lewat field `e`.
      final event = decoded['e'];
      if (event == 'kline') {
        final k = decoded['k'] as Map<String, dynamic>;
        final symbol = (decoded['s'] ?? k['s']).toString();
        _candleController.add(WsCandleEvent(symbol, Candle.fromWsKline(k)));
      } else if (event == '24hrMiniTicker') {
        _tickerController.add(WsTickerEvent(SymbolTicker.fromMiniTicker(decoded)));
      } else if (event == 'trade') {
        final symbol = decoded['s'].toString();
        final price = double.tryParse(decoded['p'].toString());
        if (price != null) _tradeController.add(WsTradeEvent(symbol, price));
      } else if (decoded.containsKey('stream')) {
        // Fallback untuk format combined-stream (jika endpoint diganti).
        final data = decoded['data'];
        final stream = decoded['stream'] as String? ?? '';
        if (data is! Map<String, dynamic>) return;
        if (stream.contains('@kline')) {
          final k = data['k'] as Map<String, dynamic>;
          _candleController
              .add(WsCandleEvent((data['s'] ?? k['s']).toString(),
                  Candle.fromWsKline(k)));
        } else if (stream.contains('@miniTicker')) {
          _tickerController
              .add(WsTickerEvent(SymbolTicker.fromMiniTicker(data)));
        } else if (stream.contains('@trade')) {
          final price = double.tryParse(data['p'].toString());
          if (price != null) {
            _tradeController
                .add(WsTradeEvent((data['s'] ?? '').toString(), price));
          }
        }
      }
    } catch (_) {
      // Abaikan pesan yang tak dapat diparse.
    }
  }

  void _handleDisconnect() {
    _statusController.add(WsStatus.disconnected);
    _sub?.cancel();
    _sub = null;
    _socket = null;
    if (_closedByUser) return;

    _reconnectAttempt++;
    final delaySec = (1 << _reconnectAttempt).clamp(1, 30);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_closedByUser) _openConnection();
    });
  }

  /// Ganti daftar simbol yang dipantau. Bila soket hidup, lakukan
  /// UNSUBSCRIBE stream lama lalu SUBSCRIBE stream baru tanpa reconnect.
  Future<void> updateSymbols(List<String> newSymbols) async {
    final oldStreams = _streamsFor(symbols);
    symbols = newSymbols;
    if (_closedByUser) return;
    if (_socket != null) {
      _sendUnsubscribe(oldStreams);
      _sendSubscribe(_streamsFor(newSymbols));
    } else {
      await _openConnection();
    }
  }

  /// Berlangganan stream tambahan (mis. `btcusdt@trade`) TANPA mengubah daftar
  /// [symbols] utama. Aman dipanggil walau soket sedang tersambung.
  void addStreams(List<String> streams) {
    if (streams.isEmpty || _closedByUser) return;
    _sendSubscribe(streams);
  }

  /// Batalkan langganan stream tambahan.
  void removeStreams(List<String> streams) {
    if (streams.isEmpty || _closedByUser) return;
    _sendUnsubscribe(streams);
  }

  Future<void> _teardownSocket() async {
    await _sub?.cancel();
    _sub = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> close() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    await _teardownSocket();
    _httpClient?.close(force: true);
    await _candleController.close();
    await _tickerController.close();
    await _tradeController.close();
    await _statusController.close();
  }
}
