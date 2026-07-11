import '../config/app_config.dart';

/// Status kesehatan sistem real-time.
enum HealthStatus { healthy, degraded, tripped }

/// Circuit breaker sederhana: memantau kesehatan proxy/REST, WebSocket, dan
/// keterlambatan candle. Saat "tripped", emisi sinyal ditahan (mode aman) agar
/// sistem tidak memaksa mengirim sinyal di atas data/koneksi yang buruk.
///
/// Singleton ringan agar dapat dibagi antara UI-isolate & background-isolate
/// (state per-isolate; keputusan bersifat sesaat, bukan persisten).
class SystemHealth {
  SystemHealth._();
  static final SystemHealth instance = SystemHealth._();

  int _consecutiveRestFailures = 0;
  bool _wsConnected = true;
  int _wsDownSince = 0; // epoch ms, 0 bila tersambung
  int _lastDataMs = 0; // epoch ms data segar terakhir

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // --- Pembaruan sinyal kesehatan ---
  void recordRestSuccess() {
    _consecutiveRestFailures = 0;
    _lastDataMs = _now();
  }

  void recordRestFailure() => _consecutiveRestFailures++;

  /// Data segar diterima (candle/ticker) → reset penanda keterlambatan.
  void recordData() => _lastDataMs = _now();

  void setWsConnected(bool connected) {
    if (connected) {
      _wsConnected = true;
      _wsDownSince = 0;
    } else {
      if (_wsConnected) _wsDownSince = _now(); // baru saja putus
      _wsConnected = false;
    }
  }

  /// Reset penuh (mis. saat init ulang).
  void reset() {
    _consecutiveRestFailures = 0;
    _wsConnected = true;
    _wsDownSince = 0;
    _lastDataMs = 0;
  }

  // --- Evaluasi status ---
  HealthStatus status({int? intervalMs}) {
    final now = _now();
    final restTripped =
        _consecutiveRestFailures >= AppConfig.cbMaxRestFailures;
    final wsTripped = !_wsConnected &&
        _wsDownSince > 0 &&
        (now - _wsDownSince) > AppConfig.cbMaxWsDownMs;
    final delayTripped = intervalMs != null &&
        _lastDataMs > 0 &&
        (now - _lastDataMs) > AppConfig.cbCandleDelayFactor * intervalMs;

    if (restTripped || wsTripped || delayTripped) return HealthStatus.tripped;
    if (_consecutiveRestFailures > 0 || !_wsConnected) {
      return HealthStatus.degraded;
    }
    return HealthStatus.healthy;
  }

  /// Apakah emisi sinyal harus ditahan (mode aman).
  bool signalsHeld({int? intervalMs}) =>
      status(intervalMs: intervalMs) == HealthStatus.tripped;

  /// Ringkasan alasan untuk UI/log.
  String reason({int? intervalMs}) {
    final reasons = <String>[];
    if (_consecutiveRestFailures >= AppConfig.cbMaxRestFailures) {
      reasons.add('proxy/REST gagal $_consecutiveRestFailures×');
    }
    if (!_wsConnected) reasons.add('WebSocket terputus');
    if (intervalMs != null &&
        _lastDataMs > 0 &&
        (_now() - _lastDataMs) > AppConfig.cbCandleDelayFactor * intervalMs) {
      reasons.add('data candle terlambat');
    }
    return reasons.isEmpty ? 'sehat' : reasons.join(', ');
  }
}
