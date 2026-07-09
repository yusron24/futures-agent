import '../config/app_config.dart';
import '../strategies/strategy_registry.dart';
import 'hive_cache.dart';

/// Repositori pengaturan pengguna yang bertahan lintas sesi (Hive).
class SettingsRepository {
  static const _kEnabledStrategies = 'enabled_strategies';
  static const _kSymbols = 'symbols';
  static const _kRiskPercent = 'risk_percent';
  static const _kCapital = 'sim_capital';
  static const _kSound = 'sound';
  static const _kSoundName = 'sound_name';
  static const _kVibration = 'vibration';
  static const _kNotifications = 'notifications';

  final _box = HiveCache.settings();

  // --- Strategi aktif ---
  List<String> get enabledStrategies {
    final stored = _box.get(_kEnabledStrategies);
    if (stored is List) {
      return stored.map((e) => e.toString()).toList();
    }
    // Default: semua aktif.
    return StrategyRegistry.allIds;
  }

  set enabledStrategies(List<String> ids) =>
      _box.put(_kEnabledStrategies, ids);

  bool isStrategyEnabled(String id) => enabledStrategies.contains(id);

  void setStrategyEnabled(String id, bool enabled) {
    final set = enabledStrategies.toSet();
    if (enabled) {
      set.add(id);
    } else {
      set.remove(id);
    }
    enabledStrategies = set.toList();
  }

  // --- Simbol dipantau ---
  List<String> get symbols {
    final stored = _box.get(_kSymbols);
    if (stored is List && stored.isNotEmpty) {
      return stored.map((e) => e.toString()).toList();
    }
    return List<String>.from(AppConfig.defaultSymbols);
  }

  set symbols(List<String> value) => _box.put(_kSymbols, value);

  // --- Manajemen risiko ---
  /// Persentase risiko per trade (dari modal simulasi).
  double get riskPercent => (_box.get(_kRiskPercent) as num?)?.toDouble() ?? 1.0;
  set riskPercent(double v) => _box.put(_kRiskPercent, v);

  double get simCapital => (_box.get(_kCapital) as num?)?.toDouble() ?? 1000.0;
  set simCapital(double v) => _box.put(_kCapital, v);

  // --- Notifikasi ---
  bool get notificationsEnabled =>
      _box.get(_kNotifications, defaultValue: true) as bool;
  set notificationsEnabled(bool v) => _box.put(_kNotifications, v);

  bool get soundEnabled => _box.get(_kSound, defaultValue: true) as bool;
  set soundEnabled(bool v) => _box.put(_kSound, v);

  /// Nama file suara notifikasi di assets/sounds (tanpa path).
  String get soundName =>
      _box.get(_kSoundName, defaultValue: 'alert.mp3') as String;
  set soundName(String v) => _box.put(_kSoundName, v);

  bool get vibrationEnabled =>
      _box.get(_kVibration, defaultValue: true) as bool;
  set vibrationEnabled(bool v) => _box.put(_kVibration, v);

  /// Ukuran posisi simulasi berdasarkan risiko: jumlah modal yang dipertaruhkan.
  double riskAmount() => simCapital * (riskPercent / 100.0);
}
