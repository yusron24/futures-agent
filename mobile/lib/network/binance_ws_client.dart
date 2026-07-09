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

/// Status koneksi WebSocket untuk indikator UI.
enum WsStatus { connecting, connected, disconnected }

/// Klien WebSocket Binance dengan combined streams (kline 1h + miniTicker),
/// diarahkan melalui proxy HTTP.
///
/// Koneksi wss ditunnel melalui proxy menggunakan HTTP CONNECT: HttpClient
/// kustom ([ProxyHttpClient]) diserahkan ke [WebSocket.connect] via
/// `customClient`, sehingga handshake TLS + upgrade WebSocket berlangsung di
/// dalam terowongan CONNECT ke proxy. Pendekatan ini menjaga byte frame awal
/// tidak hilang (ditangani penuh oleh stack HttpClient), sementara mekanisme
/// CONNECT manual didemonstrasikan terpisah di [ProxyConnectTunnel].
class BinanceWsClient {
  BinanceWsClient(this.symbols);

  List<String> symbols;

  WebSocket? _socket;
  StreamSubscription? _sub;
  HttpClient? _httpClient;
  bool _closedByUser = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  final _candleController = StreamController<WsCandleEvent>.broadcast();
  final _tickerController = StreamController<WsTickerEvent>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<WsCandleEvent> get candleStream => _candleController.stream;
  Stream<WsTickerEvent> get tickerStream => _tickerController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;

  /// URL combined-stream untuk kline_<interval> + miniTicker semua simbol.
  Uri get _streamUri {
    final streams = <String>[];
    for (final s in symbols) {
      final lower = s.toLowerCase();
      streams.add('$lower@kline_${AppConfig.interval}');
      streams.add('$lower@miniTicker');
    }
    return Uri.parse(
      '${AppConfig.wsBaseUrl}/stream?streams=${streams.join('/')}',
    );
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
      // WebSocket.connect memakai HttpClient yang sudah dikonfigurasi proxy,
      // jadi handshake wss ditunnel via HTTP CONNECT ke proxy.
      final socket = await WebSocket.connect(
        _streamUri.toString(),
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
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String) as Map<String, dynamic>;
      final data = decoded['data'];
      final stream = decoded['stream'] as String? ?? '';
      if (data is! Map<String, dynamic>) return;

      if (stream.contains('@kline')) {
        final k = data['k'] as Map<String, dynamic>;
        final symbol = (data['s'] ?? k['s']).toString();
        _candleController.add(WsCandleEvent(symbol, Candle.fromWsKline(k)));
      } else if (stream.contains('@miniTicker')) {
        _tickerController.add(WsTickerEvent(SymbolTicker.fromMiniTicker(data)));
      }
    } catch (_) {
      // Abaikan pesan yang tak dapat diparse (mis. pong / kontrol).
    }
  }

  void _handleDisconnect() {
    _statusController.add(WsStatus.disconnected);
    _sub?.cancel();
    _sub = null;
    _socket = null;
    if (_closedByUser) return;

    // Reconnect dengan exponential backoff (maks 30 dtk).
    _reconnectAttempt++;
    final delaySec = (1 << _reconnectAttempt).clamp(1, 30);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_closedByUser) _openConnection();
    });
  }

  /// Ganti daftar simbol yang dipantau lalu sambung ulang.
  Future<void> updateSymbols(List<String> newSymbols) async {
    symbols = newSymbols;
    if (!_closedByUser) {
      await _teardownSocket();
      await _openConnection();
    }
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
    await _statusController.close();
  }
}
