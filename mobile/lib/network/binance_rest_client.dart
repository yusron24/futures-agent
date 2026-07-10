import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../models/candle.dart';
import '../models/symbol_ticker.dart';
import 'proxy_http_client.dart';

/// Klien REST Binance. Semua permintaan melewati proxy aplikasi lewat
/// [ProxyHttpClient]. Menyediakan klines (candle 1 jam), ticker 24 jam, dan
/// exchange info.
class BinanceRestClient {
  BinanceRestClient({HttpClient? httpClient})
      : _client = httpClient ?? ProxyHttpClient.create();

  final HttpClient _client;

  /// Ambil hingga [limit] candle untuk [symbol] pada interval yang dikonfigurasi.
  /// Binance membatasi 1000 candle per permintaan; untuk >1000 dilakukan paging.
  Future<List<Candle>> fetchKlines(
    String symbol, {
    String interval = AppConfig.defaultInterval,
    int limit = AppConfig.candleWindow,
    int? endTime,
  }) async {
    if (limit <= 1000) {
      return _fetchKlinesPage(symbol, interval, limit, endTime);
    }

    // Paging mundur untuk memenuhi jendela besar (>1000).
    final all = <Candle>[];
    int? cursorEnd = endTime;
    int remaining = limit;
    while (remaining > 0) {
      final take = remaining > 1000 ? 1000 : remaining;
      final page = await _fetchKlinesPage(symbol, interval, take, cursorEnd);
      if (page.isEmpty) break;
      all.insertAll(0, page);
      remaining -= page.length;
      cursorEnd = page.first.openTime - 1; // sebelum candle paling awal
      if (page.length < take) break; // tidak ada data lebih lama
    }
    // Deduplikasi & urutkan.
    final byTime = <int, Candle>{for (final c in all) c.openTime: c};
    final sorted = byTime.values.toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));
    return sorted;
  }

  Future<List<Candle>> _fetchKlinesPage(
    String symbol,
    String interval,
    int limit,
    int? endTime,
  ) async {
    final params = <String, String>{
      'symbol': symbol,
      'interval': interval,
      'limit': '$limit',
      if (endTime != null) 'endTime': '$endTime',
    };
    final data = await _getJson('/api/v3/klines', params) as List<dynamic>;
    return data
        .map((e) => Candle.fromRestArray(e as List<dynamic>))
        .toList(growable: false);
  }

  /// Ticker 24 jam untuk sekumpulan simbol.
  ///
  /// Memakai `type=MINI` agar payload jauh lebih ringkas (tanpa bid/ask,
  /// weighted average, dll) sehingga hemat bandwidth lewat proxy. Persentase
  /// perubahan dihitung dari openPrice/lastPrice di sisi klien.
  Future<List<SymbolTicker>> fetch24hTickers(List<String> symbols) async {
    if (symbols.isEmpty) return const [];
    // Binance mendukung parameter `symbols=[...]` (JSON array, tanpa spasi).
    final encoded = jsonEncode(symbols);
    final data = await _getJson(
      '/api/v3/ticker/24hr',
      {'symbols': encoded, 'type': 'MINI'},
    );
    final list = data is List ? data : [data];
    return list
        .map((e) => SymbolTicker.fromRest24h(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Ambil [limit] simbol spot dengan quote [AppConfig.quoteAsset] yang
  /// **volume 24 jam-nya tertinggi** di seluruh Binance.
  ///
  /// Langkah:
  ///  1. `exchangeInfo` -> himpunan simbol SPOT berstatus TRADING dengan
  ///     quoteAsset yang diminta, mengecualikan leveraged token (UP/DOWN/
  ///     BULL/BEAR) yang bukan pasar spot murni.
  ///  2. `ticker/24hr` (semua simbol) -> urutkan berdasarkan `quoteVolume`
  ///     (nilai USDT), ambil [limit] teratas.
  Future<List<String>> fetchTopSymbolsByVolume({
    int limit = AppConfig.topPairsCount,
    String quote = AppConfig.quoteAsset,
  }) async {
    // 1) Simbol valid dari exchangeInfo.
    final info =
        await _getJson('/api/v3/exchangeInfo', const {}) as Map<String, dynamic>;
    final valid = <String>{};
    for (final s in (info['symbols'] as List)) {
      final m = s as Map<String, dynamic>;
      final symbol = m['symbol'] as String;
      final tradingOk = m['status'] == 'TRADING';
      final spotOk = m['isSpotTradingAllowed'] == true;
      final quoteOk = m['quoteAsset'] == quote;
      if (tradingOk && spotOk && quoteOk && !_isLeveragedToken(symbol, quote)) {
        valid.add(symbol);
      }
    }

    // 2) Volume 24 jam untuk semua simbol, lalu diperingkat.
    final all = await _getJson('/api/v3/ticker/24hr', const {});
    final tickers = (all as List).cast<Map<String, dynamic>>();
    final ranked = tickers
        .where((t) => valid.contains(t['symbol']))
        .toList()
      ..sort((a, b) => _quoteVolume(b).compareTo(_quoteVolume(a)));

    return ranked
        .take(limit)
        .map((t) => t['symbol'] as String)
        .toList(growable: false);
  }

  static double _quoteVolume(Map<String, dynamic> t) =>
      double.tryParse(t['quoteVolume']?.toString() ?? '') ?? 0;

  /// Leveraged token (mis. BTCUPUSDT / ETHDOWNUSDT / xxxBULLUSDT / xxxBEARUSDT).
  static bool _isLeveragedToken(String symbol, String quote) {
    if (!symbol.endsWith(quote)) return false;
    final base = symbol.substring(0, symbol.length - quote.length);
    return base.endsWith('UP') ||
        base.endsWith('DOWN') ||
        base.endsWith('BULL') ||
        base.endsWith('BEAR');
  }

  /// Uji konektivitas (ping) — memastikan proxy + jaringan hidup.
  Future<bool> ping() async {
    try {
      await _getJson('/api/v3/ping', const {});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Waktu server (ms). Berguna menghitung batas candle 1 jam.
  Future<int> serverTime() async {
    final data = await _getJson('/api/v3/time', const {}) as Map<String, dynamic>;
    return (data['serverTime'] as num).toInt();
  }

  // ---------------------------------------------------------------------------

  Future<dynamic> _getJson(String path, Map<String, String> params) async {
    final uri = Uri.parse(AppConfig.restBaseUrl).replace(
      path: path,
      queryParameters: params.isEmpty ? null : params,
    );

    HttpClientResponse? response;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final request = await _client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'scalp-signals/1.0');
        response = await request.close();

        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) {
          return jsonDecode(body);
        }
        // 429/418 -> rate limit; hormati Retry-After bila ada.
        if (response.statusCode == 429 || response.statusCode == 418) {
          final retry = int.tryParse(
                  response.headers.value('retry-after') ?? '') ??
              (attempt + 1);
          await Future<void>.delayed(Duration(seconds: retry.clamp(1, 30)));
          continue;
        }
        throw HttpException(
          'Binance ${response.statusCode} untuk $path: $body',
        );
      } on SocketException catch (_) {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(Duration(seconds: (attempt + 1) * 2));
      }
    }
    throw HttpException('Gagal GET $path setelah 3 percobaan');
  }

  void close() => _client.close(force: true);
}
