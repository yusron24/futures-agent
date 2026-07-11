import 'package:flutter_test/flutter_test.dart';
import 'package:scalp_signals/services/system_health.dart';

void main() {
  final h = SystemHealth.instance;
  setUp(h.reset);

  group('SystemHealth circuit breaker', () {
    test('awal sehat, tidak menahan sinyal', () {
      h.recordData();
      expect(h.status(), HealthStatus.healthy);
      expect(h.signalsHeld(), false);
    });

    test('REST gagal beruntun → tripped lalu pulih', () {
      h.recordRestFailure();
      h.recordRestFailure();
      expect(h.status(), HealthStatus.degraded); // < ambang (3)
      h.recordRestFailure();
      expect(h.status(), HealthStatus.tripped); // ≥ 3
      expect(h.signalsHeld(), true);

      h.recordRestSuccess();
      expect(h.status(), HealthStatus.healthy);
      expect(h.signalsHeld(), false);
    });

    test('WS terputus → degraded (belum tripped tanpa durasi)', () {
      h.setWsConnected(false);
      expect(h.status(), HealthStatus.degraded);
      h.setWsConnected(true);
      expect(h.status(), HealthStatus.healthy);
    });
  });
}
