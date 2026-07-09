import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../data/candle_repository.dart';
import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../models/signal.dart';
import '../models/symbol_ticker.dart';
import '../network/binance_rest_client.dart';
import '../network/binance_ws_client.dart';
import '../services/notification_service.dart';
import '../signals/signal_engine.dart';

/// State pusat aplikasi: mengorkestrasi REST + WebSocket (via proxy),
/// pembaruan candle, pembuatan sinyal, notifikasi, dan menyediakan data untuk
/// seluruh UI melalui [ChangeNotifier].
class AppState extends ChangeNotifier {
  AppState({
    required this.settings,
    required this.candles,
    required this.history,
  })  : engine = SignalEngine(settings, history),
        rest = BinanceRestClient();

  final SettingsRepository settings;
  final CandleRepository candles;
  final SignalHistoryRepository history;
  final SignalEngine engine;
  final BinanceRestClient rest;
  BinanceWsClient? _ws;

  final Map<String, SymbolTicker> tickers = {};
  final Map<String, SymbolEvaluation> evaluations = {};

  WsStatus wsStatus = WsStatus.disconnected;
  bool isOnline = true;
  bool isLoading = true;
  String? errorMessage;

  Timer? _uiCoalesce;
  final Set<StreamSubscription> _subs = {};

  List<String> get symbols => settings.symbols;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    // 1) Muat cache dulu agar UI langsung terisi (mendukung offline).
    for (final s in symbols) {
      final cached = await candles.loadCached(s);
      if (cached.isNotEmpty) {
        _evaluateSymbol(s, notify: false);
      }
    }
    notifyListeners();

    // 2) Segarkan dari REST (klines + ticker) melalui proxy.
    await refreshAll();

    // 3) Sambungkan WebSocket streaming.
    await _connectWs();

    isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    try {
      final ticks = await rest.fetch24hTickers(symbols);
      for (final t in ticks) {
        tickers[t.symbol] = t;
      }
      for (final s in symbols) {
        final kl = await rest.fetchKlines(s, limit: AppConfig.candleWindow);
        if (kl.isNotEmpty) {
          await candles.replaceAll(s, kl);
          await _resolveAndEvaluate(s, notify: false);
        }
      }
      isOnline = true;
      errorMessage = null;
    } catch (e) {
      isOnline = false;
      errorMessage = 'Gagal memuat data (offline?). Menampilkan cache.';
    }
    notifyListeners();
  }

  Future<void> _connectWs() async {
    await _ws?.close();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    final ws = BinanceWsClient(symbols);
    _ws = ws;
    _subs.add(ws.candleStream.listen(_onCandle));
    _subs.add(ws.tickerStream.listen(_onTicker));
    _subs.add(ws.statusStream.listen((st) {
      wsStatus = st;
      _scheduleUiUpdate();
    }));
    await ws.connect();
  }

  // ---------------------------------------------------------------------------
  // Stream handlers
  // ---------------------------------------------------------------------------

  Future<void> _onCandle(WsCandleEvent e) async {
    final newlyClosed = await candles.applyUpdate(e.symbol, e.candle);
    if (newlyClosed != null) {
      // Candle 1 jam baru ditutup -> jalankan strategi & mungkin kirim sinyal.
      await _resolveAndEvaluate(e.symbol, notify: true, emitSignal: true);
    } else {
      _scheduleUiUpdate();
    }
  }

  void _onTicker(WsTickerEvent e) {
    tickers[e.ticker.symbol] = e.ticker;
    _scheduleUiUpdate();
  }

  Future<void> _resolveAndEvaluate(
    String symbol, {
    required bool notify,
    bool emitSignal = false,
  }) async {
    final closed = candles.closedCandles(symbol);
    if (closed.isEmpty) return;

    // Selesaikan sinyal pending terhadap candle terbaru (update akurasi).
    await history.resolvePending(symbol, closed);

    _evaluateSymbol(symbol, notify: false);

    if (emitSignal) {
      final eval = evaluations[symbol];
      if (eval != null && eval.signal.isActionable) {
        await history.add(eval.signal);
        if (settings.notificationsEnabled) {
          await NotificationService.instance.showSignal(
            eval.signal,
            sound: settings.soundEnabled,
            vibrate: settings.vibrationEnabled,
            soundAsset: settings.soundName,
          );
        }
      }
    }
    if (notify) notifyListeners();
  }

  void _evaluateSymbol(String symbol, {required bool notify}) {
    final closed = candles.closedCandles(symbol);
    if (closed.length < 30) return;
    evaluations[symbol] = engine.evaluate(symbol, closed);
    if (notify) notifyListeners();
  }

  /// Coalesce pembaruan UI frekuensi tinggi (ticker/candle berjalan).
  void _scheduleUiUpdate() {
    _uiCoalesce?.cancel();
    _uiCoalesce = Timer(const Duration(milliseconds: 400), () {
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // Aksi dari UI
  // ---------------------------------------------------------------------------

  SymbolEvaluation? evaluationFor(String symbol) => evaluations[symbol];
  SymbolTicker? tickerFor(String symbol) => tickers[symbol];

  Signal? signalFor(String symbol) => evaluations[symbol]?.signal;

  Future<void> updateSymbols(List<String> newSymbols) async {
    settings.symbols = newSymbols;
    for (final s in newSymbols) {
      await candles.loadCached(s);
    }
    await refreshAll();
    await _ws?.updateSymbols(newSymbols);
    notifyListeners();
  }

  void toggleStrategy(String id, bool enabled) {
    settings.setStrategyEnabled(id, enabled);
    for (final s in symbols) {
      _evaluateSymbol(s, notify: false);
    }
    notifyListeners();
  }

  /// Paksa evaluasi ulang semua simbol (mis. setelah ubah pengaturan risiko).
  void reevaluateAll() {
    for (final s in symbols) {
      _evaluateSymbol(s, notify: false);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _uiCoalesce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _ws?.close();
    rest.close();
    super.dispose();
  }
}
