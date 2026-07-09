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
  Timer? _tickerPollTimer;
  final Set<StreamSubscription> _subs = {};

  List<String> get symbols => settings.symbols;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Sedang menyusun ulang daftar pair top-volume.
  bool isResolvingSymbols = false;

  int get monitoredCount => symbols.length;

  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    // 0) Mode top-volume: susun daftar pair top-volume dari seluruh Binance.
    //    Jika gagal (offline), pakai daftar tersimpan / default.
    if (settings.useTopVolume) {
      await _resolveTopSymbols(silent: true);
    }

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

  /// Ambil ulang daftar pair top-volume dan simpan ke pengaturan.
  Future<void> _resolveTopSymbols({bool silent = false}) async {
    isResolvingSymbols = true;
    if (!silent) notifyListeners();
    try {
      final top = await rest.fetchTopSymbolsByVolume(
        limit: settings.topPairsCount,
      );
      if (top.isNotEmpty) {
        settings.resolvedTopSymbols = top;
        isOnline = true;
        errorMessage = null;
      }
    } catch (_) {
      // Biarkan daftar tersimpan sebelumnya; jangan gagalkan startup.
    } finally {
      isResolvingSymbols = false;
    }
  }

  /// Dipanggil dari UI: perbarui peringkat top-volume lalu muat ulang data & WS.
  Future<void> refreshTopSymbols() async {
    if (!settings.useTopVolume) return;
    await _resolveTopSymbols();
    for (final s in symbols) {
      await candles.loadCached(s);
    }
    await refreshAll();
    await _ws?.updateSymbols(symbols);
    notifyListeners();
  }

  /// Ganti mode simbol (top-volume / custom) lalu terapkan.
  Future<void> setSymbolMode(String mode) async {
    settings.symbolMode = mode;
    if (mode == SettingsRepository.modeTopVolume &&
        settings.resolvedTopSymbols.isEmpty) {
      await _resolveTopSymbols();
    }
    for (final s in symbols) {
      await candles.loadCached(s);
    }
    await refreshAll();
    await _ws?.updateSymbols(symbols);
    notifyListeners();
  }

  Future<void> refreshAll() async {
    final syms = symbols;
    try {
      // Ticker awal (dipecah agar parameter tidak terlalu panjang).
      for (var i = 0; i < syms.length; i += 50) {
        final chunk =
            syms.sublist(i, i + 50 > syms.length ? syms.length : i + 50);
        final ticks = await rest.fetch24hTickers(chunk);
        for (final t in ticks) {
          tickers[t.symbol] = t;
        }
      }

      // Klines dengan konkurensi terbatas. Simbol yang cache-nya sudah mutakhir
      // (dijaga live oleh WebSocket) DILEWATI agar tidak mengunduh ulang —
      // ini membuat refresh nyaris instan & sangat hemat bandwidth.
      await _runPooled<String>(
        syms,
        AppConfig.restFetchConcurrency,
        (s) async {
          if (_isFresh(s)) {
            _evaluateSymbol(s, notify: false);
            return;
          }
          final kl =
              await rest.fetchKlines(s, limit: AppConfig.restWarmupCandles);
          if (kl.isNotEmpty) {
            await candles.replaceAll(s, kl);
            await _resolveAndEvaluate(s, notify: false);
          }
        },
      );
      isOnline = true;
      errorMessage = null;
    } catch (e) {
      isOnline = false;
      errorMessage = 'Gagal memuat data (offline?). Menampilkan cache.';
    }
    notifyListeners();
  }

  /// Apakah cache candle sebuah simbol sudah mutakhir (candle 1 jam terakhir
  /// yang tertutup sudah ada) sehingga tidak perlu di-fetch ulang.
  bool _isFresh(String symbol) {
    final closed = candles.closedCandles(symbol);
    if (closed.length < AppConfig.minReadyCandles) return false;
    const hourMs = 3600000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final currentHourStart = (now ~/ hourMs) * hourMs;
    final expectedLastClosedOpen = currentHourStart - hourMs;
    return closed.last.openTime >= expectedLastClosedOpen;
  }

  /// Jalankan [task] atas [items] dengan paling banyak [concurrency] bersamaan.
  Future<void> _runPooled<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T) task,
  ) async {
    if (items.isEmpty) return;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) break;
        try {
          await task(items[i]);
        } catch (_) {
          // Lewati simbol yang gagal, lanjut ke berikutnya.
        }
      }
    }

    final n = concurrency.clamp(1, items.length);
    await Future.wait(List.generate(n, (_) => worker()));
  }

  Future<void> _connectWs() async {
    await _ws?.close();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    // Mode hemat bandwidth: matikan stream miniTicker (firehose ~1 pesan/detik
    // per simbol). Harga tetap live dari stream kline; perubahan 24 jam
    // diperbarui berkala via REST ringan.
    final dataSaver = settings.dataSaver;
    final ws = BinanceWsClient(symbols, includeMiniTicker: !dataSaver);
    _ws = ws;
    _subs.add(ws.candleStream.listen(_onCandle));
    _subs.add(ws.tickerStream.listen(_onTicker));
    _subs.add(ws.statusStream.listen((st) {
      wsStatus = st;
      _scheduleUiUpdate();
    }));
    await ws.connect();

    _tickerPollTimer?.cancel();
    if (dataSaver) {
      _tickerPollTimer = Timer.periodic(
        const Duration(seconds: AppConfig.tickerPollSeconds),
        (_) => _refreshTickersOnly(),
      );
    }
  }

  /// Ambil ulang HANYA ticker 24 jam (ringan) — dipakai saat mode hemat
  /// bandwidth untuk memperbarui persentase perubahan tanpa stream miniTicker.
  Future<void> _refreshTickersOnly() async {
    final syms = symbols;
    try {
      for (var i = 0; i < syms.length; i += 50) {
        final chunk =
            syms.sublist(i, i + 50 > syms.length ? syms.length : i + 50);
        final ticks = await rest.fetch24hTickers(chunk);
        for (final t in ticks) {
          final existing = tickers[t.symbol];
          // Pertahankan harga terbaru dari kline; ambil % perubahan dari REST.
          tickers[t.symbol] = existing == null
              ? t
              : existing.copyWith(
                  changePercent24h: t.changePercent24h,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );
        }
      }
      isOnline = true;
    } catch (_) {
      // Abaikan; coba lagi di siklus berikutnya.
    }
    _scheduleUiUpdate();
  }

  // ---------------------------------------------------------------------------
  // Stream handlers
  // ---------------------------------------------------------------------------

  Future<void> _onCandle(WsCandleEvent e) async {
    // Jaga harga tetap live dari stream kline (penting saat miniTicker dimatikan
    // di mode hemat bandwidth). % perubahan 24 jam dipertahankan apa adanya.
    final existing = tickers[e.symbol];
    final now = DateTime.now().millisecondsSinceEpoch;
    tickers[e.symbol] = existing == null
        ? SymbolTicker(
            symbol: e.symbol,
            lastPrice: e.candle.close,
            changePercent24h: 0,
            updatedAt: now,
          )
        : existing.copyWith(lastPrice: e.candle.close, updatedAt: now);

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

  /// Terapkan perubahan mode hemat bandwidth: sambung ulang WS sesuai setelan.
  Future<void> applyDataSaver(bool enabled) async {
    settings.dataSaver = enabled;
    await _connectWs();
    notifyListeners();
  }

  @override
  void dispose() {
    _uiCoalesce?.cancel();
    _tickerPollTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _ws?.close();
    rest.close();
    super.dispose();
  }
}
