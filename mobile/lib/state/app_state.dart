import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../data/candle_repository.dart';
import '../data/settings_repository.dart';
import '../data/signal_history_repository.dart';
import '../indicators/vwap.dart';
import '../models/signal.dart';
import '../models/strategy_result.dart';
import '../models/symbol_ticker.dart';
import '../network/binance_rest_client.dart';
import '../network/binance_ws_client.dart';
import '../services/notification_service.dart';
import '../services/system_health.dart';
import '../signals/backtest_engine.dart';
import '../signals/paper_account.dart';
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

  /// Simbol yang sedang dibuka di halaman Detail (dapat stream `@trade` ekstra).
  String? _focusedSymbol;

  final Map<String, SymbolTicker> tickers = {};
  final Map<String, SymbolEvaluation> evaluations = {};

  /// Candle terakhir (openTime) yang sudah dinotifikasi per simbol — mencegah
  /// notifikasi dobel bila dua jalur memproses candle yang sama.
  final Map<String, int> _lastNotifiedCandle = {};

  /// Notifier harga per-simbol: memungkinkan tiap baris/harga di UI rebuild
  /// SEKETIKA saat ada tick, tanpa merebuild seluruh dashboard (mulus + hemat).
  final Map<String, ValueNotifier<SymbolTicker?>> _priceNotifiers = {};

  /// Listenable harga realtime satu simbol (dibuat lazy).
  ValueListenable<SymbolTicker?> priceListenable(String symbol) =>
      _priceNotifiers.putIfAbsent(
          symbol, () => ValueNotifier<SymbolTicker?>(tickers[symbol]));

  /// Satu-satunya penulis harga: perbarui map + notifier simbol seketika.
  void _pushPrice(SymbolTicker t) {
    tickers[t.symbol] = t;
    _priceNotifiers[t.symbol]?.value = t;
  }

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
    // Terapkan konfigurasi VWAP sebelum evaluasi pertama agar konsisten.
    applyVwapSettings();
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

  /// Dipanggil saat aplikasi kembali ke depan: sambung ulang WebSocket (soket
  /// lama biasanya sudah mati saat di-background) dan segarkan data. Fetch
  /// klines dilewati untuk simbol yang cache-nya sudah mutakhir sehingga cepat.
  Future<void> onResume() async {
    await refreshAll();
    await _connectWs();
    notifyListeners();
  }

  /// Dipanggil saat aplikasi ke latar belakang. Foreground service (bila aktif)
  /// yang menangani pemantauan; WS UI akan disambung ulang saat resume.
  void onPause() {
    // No-op yang disengaja: OS menangguhkan isolate; soket dibiarkan.
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
          _pushPrice(t);
        }
      }

      // Klines dengan konkurensi tinggi (dapat diatur) agar refresh cepat.
      // Simbol yang cache-nya sudah mutakhir (dijaga live oleh WebSocket)
      // tetap dilewati agar tidak mengunduh ulang secara sia-sia.
      await _runPooled<String>(
        syms,
        settings.fetchConcurrency,
        (s) async {
          if (_isFresh(s)) {
            _evaluateSymbol(s, notify: false);
            return;
          }
          final kl = await rest.fetchKlines(
            s,
            limit: AppConfig.restWarmupCandles,
            interval: settings.interval,
          );
          if (kl.isNotEmpty) {
            await candles.replaceAll(s, kl);
            await _resolveAndEvaluate(s, notify: false);
          }
        },
      );
      isOnline = true;
      errorMessage = null;
      SystemHealth.instance.recordRestSuccess();
    } catch (e) {
      isOnline = false;
      errorMessage = 'Gagal memuat data (offline?). Menampilkan cache.';
      SystemHealth.instance.recordRestFailure();
    }
    notifyListeners();
  }

  /// Apakah sistem sedang menahan emisi sinyal (mode aman circuit breaker).
  bool get signalsHeld => SystemHealth.instance
      .signalsHeld(intervalMs: AppConfig.intervalMs(settings.interval));

  /// Alasan mode aman untuk banner/log.
  String get healthReason => SystemHealth.instance
      .reason(intervalMs: AppConfig.intervalMs(settings.interval));

  /// Apakah cache candle sebuah simbol sudah mutakhir (candle timeframe terakhir
  /// yang tertutup sudah ada) sehingga tidak perlu di-fetch ulang.
  bool _isFresh(String symbol) {
    final closed = candles.closedCandles(symbol);
    if (closed.length < AppConfig.minReadyCandles) return false;
    final stepMs = AppConfig.intervalMs(settings.interval);
    final now = DateTime.now().millisecondsSinceEpoch;
    final currentStepStart = (now ~/ stepMs) * stepMs;
    final expectedLastClosedOpen = currentStepStart - stepMs;
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
    final ws = BinanceWsClient(
      symbols,
      includeMiniTicker: !dataSaver,
      interval: settings.interval,
    );
    _ws = ws;
    _subs.add(ws.candleStream.listen(_onCandle));
    _subs.add(ws.tickerStream.listen(_onTicker));
    _subs.add(ws.tradeStream.listen(_onTrade));
    _subs.add(ws.statusStream.listen((st) {
      wsStatus = st;
      SystemHealth.instance.setWsConnected(st == WsStatus.connected);
      _scheduleUiUpdate();
    }));
    await ws.connect();

    // Pulihkan langganan trade untuk simbol yang sedang dibuka di Detail.
    final focused = _focusedSymbol;
    if (focused != null) {
      ws.addStreams(['${focused.toLowerCase()}@trade']);
    }

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
          _pushPrice(existing == null
              ? t
              : existing.copyWith(
                  changePercent24h: t.changePercent24h,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ));
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
    SystemHealth.instance.recordData(); // data segar → reset penanda keterlambatan
    // Jaga harga tetap live dari stream kline (penting saat miniTicker dimatikan
    // di mode hemat bandwidth). % perubahan 24 jam dipertahankan apa adanya.
    final existing = tickers[e.symbol];
    final now = DateTime.now().millisecondsSinceEpoch;
    _pushPrice(existing == null
        ? SymbolTicker(
            symbol: e.symbol,
            lastPrice: e.candle.close,
            changePercent24h: 0,
            updatedAt: now,
          )
        : existing.copyWith(lastPrice: e.candle.close, updatedAt: now));

    final newlyClosed = await candles.applyUpdate(e.symbol, e.candle);
    if (newlyClosed != null) {
      // Candle 1 jam baru ditutup -> jalankan strategi & mungkin kirim sinyal.
      await _resolveAndEvaluate(e.symbol, notify: true, emitSignal: true);
    } else {
      _scheduleUiUpdate();
    }
  }

  void _onTicker(WsTickerEvent e) {
    _pushPrice(e.ticker);
    _scheduleUiUpdate();
  }

  /// Tick harga per-transaksi (stream `@trade`) untuk simbol yang sedang dibuka
  /// di halaman Detail — update harga sangat halus tanpa merebuild dashboard.
  void _onTrade(WsTradeEvent e) {
    final existing = tickers[e.symbol];
    final now = DateTime.now().millisecondsSinceEpoch;
    _pushPrice(existing == null
        ? SymbolTicker(
            symbol: e.symbol,
            lastPrice: e.price,
            changePercent24h: 0,
            updatedAt: now,
          )
        : existing.copyWith(lastPrice: e.price, updatedAt: now));
  }

  Future<void> _resolveAndEvaluate(
    String symbol, {
    required bool notify,
    bool emitSignal = false,
  }) async {
    final closed = candles.closedCandles(symbol);
    if (closed.isEmpty) return;

    // Selesaikan sinyal pending + pasang cooldown setelah TP/SL.
    final cooldownMs = settings.cooldownEnabled
        ? settings.cooldownCandles * AppConfig.intervalMs(settings.interval)
        : 0;
    await history.resolvePending(symbol, closed, cooldownMs: cooldownMs);

    _evaluateSymbol(symbol, notify: false);

    if (emitSignal) {
      final eval = evaluations[symbol];
      if (eval != null && eval.signal.isActionable) {
        // Circuit breaker: tahan emisi saat sistem tidak sehat.
        final held = SystemHealth.instance
            .signalsHeld(intervalMs: AppConfig.intervalMs(settings.interval));
        // Anti-dup: satu emisi per candle per simbol.
        final dup = _lastNotifiedCandle[symbol] == eval.signal.timestamp;
        if (!held && !dup) {
          await history.add(eval.signal);
          _lastNotifiedCandle[symbol] = eval.signal.timestamp;
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
    }
    if (notify) notifyListeners();
  }

  void _evaluateSymbol(String symbol, {required bool notify}) {
    final closed = candles.closedCandles(symbol);
    if (closed.length < 30) return;
    evaluations[symbol] = engine.evaluate(symbol, closed);
    if (notify) notifyListeners();
  }

  /// Throttle pembaruan UI global frekuensi-tinggi (dot koneksi, banner, dll).
  ///
  /// PENTING: memakai throttle, BUKAN debounce. Debounce lama membatalkan timer
  /// pada setiap tick sehingga saat banyak simbol nge-tick < 400 ms sekali,
  /// `notifyListeners` tidak pernah menyala (UI beku, harga tampak diam sampai
  /// refresh manual). Throttle menjamin flush berkala (maks ~4×/detik).
  void _scheduleUiUpdate() {
    if (_uiCoalesce?.isActive ?? false) return; // sudah terjadwal, jangan reset
    _uiCoalesce = Timer(const Duration(milliseconds: 250), () {
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // Aksi dari UI
  // ---------------------------------------------------------------------------

  SymbolEvaluation? evaluationFor(String symbol) => evaluations[symbol];
  SymbolTicker? tickerFor(String symbol) => tickers[symbol];

  /// Buka fokus ke satu simbol (halaman Detail): langganan stream `@trade` agar
  /// harga bergerak per-transaksi (sangat halus, seperti Binance).
  void focusSymbol(String symbol) {
    if (_focusedSymbol == symbol) return;
    // Lepas fokus sebelumnya bila ada.
    final prev = _focusedSymbol;
    if (prev != null) _ws?.removeStreams(['${prev.toLowerCase()}@trade']);
    _focusedSymbol = symbol;
    _ws?.addStreams(['${symbol.toLowerCase()}@trade']);
  }

  /// Lepas fokus (keluar dari Detail): hentikan langganan `@trade`.
  void unfocusSymbol(String symbol) {
    if (_focusedSymbol != symbol) return;
    _ws?.removeStreams(['${symbol.toLowerCase()}@trade']);
    _focusedSymbol = null;
  }

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

  /// Ganti timeframe/interval candle. Karena cache candle di-key per simbol
  /// (bukan per interval), cache lama harus dikosongkan agar tidak mencampur
  /// timeframe; lalu warmup ulang via REST + sambung ulang WS.
  Future<void> setInterval(String interval) async {
    if (interval == settings.interval) return;
    if (!AppConfig.allowedIntervals.contains(interval)) return;
    settings.interval = interval;
    // Reset guard background agar candle baru diproses ulang di jam/step ini.
    settings.bgLastProcessedHour = 0;
    isLoading = true;
    evaluations.clear();
    notifyListeners();
    for (final s in symbols) {
      await candles.clear(s);
    }
    await refreshAll();
    await _connectWs();
    isLoading = false;
    notifyListeners();
  }

  // --- Fase 4: Backtest & Paper Trading ---

  /// Jalankan backtest walk-forward atas candle tersimpan sebuah simbol.
  BacktestReport runBacktest(String symbol) => BacktestRunner.run(
        symbol: symbol,
        candles: candles.closedCandles(symbol),
        settings: settings,
      );

  /// Ringkasan akun kertas (net setelah biaya) dari seluruh riwayat sinyal.
  PaperSummary paperStats() => PaperAccount.summarize(
        history.all(),
        startCapital: settings.simCapital,
        riskAmount: settings.riskAmount(),
        applyCost: AppConfig.tradeCostEnabledDefault,
      );

  /// "Reset sinyal": abaikan sinyal aktif sebuah simbol. Ditandai `ignored`
  /// (tidak ikut statistik) & disingkirkan dari dashboard; candle/strategi tetap
  /// tersimpan sehingga simbol bisa memunculkan sinyal baru kemudian.
  Future<void> ignoreSignal(String symbol) async {
    final eval = evaluations[symbol];
    final signal = eval?.signal;
    if (signal != null && signal.isActionable) {
      await history.ignore(signal);
    }
    // Ganti evaluasi jadi netral agar hilang dari dashboard sampai setup baru.
    evaluations[symbol] = SymbolEvaluation(
      Signal(
        symbol: symbol,
        direction: TradeDirection.neutral,
        entry: 0,
        stopLoss: 0,
        takeProfit: 0,
        confidence: 0,
        riskReward: 0,
        triggeredStrategies: const [],
        timestamp: signal?.timestamp ?? 0,
        note: 'Sinyal di-reset pengguna',
      ),
      eval?.results ?? const [],
    );
    notifyListeners();
  }

  /// Salin setelan VWAP pengguna ke [VwapConfig] statis (dibaca chart & strategi).
  void applyVwapSettings() {
    VwapConfig.mode = VwapConfig.modeFromString(settings.vwapMode);
    VwapConfig.period = settings.vwapPeriod;
    VwapConfig.enabledForSignals = settings.vwapEnabled;
  }

  /// Dipanggil dari Pengaturan saat setelan VWAP berubah: terapkan + evaluasi ulang.
  void refreshVwap() {
    applyVwapSettings();
    reevaluateAll();
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
    for (final n in _priceNotifiers.values) {
      n.dispose();
    }
    _ws?.close();
    rest.close();
    super.dispose();
  }
}
