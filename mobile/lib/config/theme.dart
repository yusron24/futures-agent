import 'package:flutter/material.dart';

/// Palet & tema aplikasi. Tema gelap sebagai default dengan estetika crypto
/// modern (aksen hijau/merah untuk arah trade, ungu neon untuk aksen UI).
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF121826);
  static const Color surfaceAlt = Color(0xFF1B2436);
  static const Color border = Color(0xFF243049);

  static const Color primary = Color(0xFF6C5CE7); // ungu neon
  static const Color primaryDim = Color(0xFF4B3FB0);

  static const Color buy = Color(0xFF16C784); // hijau
  static const Color sell = Color(0xFFEA3943); // merah
  static const Color neutral = Color(0xFF8A94A6); // abu

  static const Color textPrimary = Color(0xFFF5F7FB);
  static const Color textSecondary = Color(0xFF9AA6BD);
  static const Color warning = Color(0xFFF7A600);

  /// Warna arah sinyal.
  static Color forDirection(String direction) {
    switch (direction.toUpperCase()) {
      case 'BUY':
        return buy;
      case 'SELL':
        return sell;
      default:
        return neutral;
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        primary: AppColors.primary,
        secondary: AppColors.primary,
        error: AppColors.sell,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.neutral,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryDim
              : AppColors.surfaceAlt,
        ),
      ),
    );
  }
}
