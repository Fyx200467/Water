import 'package:flutter/material.dart';

/// PRD §4.3 适配深浅色模式；§4.5 全局无开屏广告、无弹窗干扰
/// 配色：以"治愈蓝 + 暖奶"为主，模拟水的清透与动物养成感
class AppTheme {
  AppTheme._();

  static const Color _primaryLight = Color(0xFF4ECDC4);
  static const Color _primaryDark = Color(0xFF2BB6A8);
  static const Color _accentLight = Color(0xFFFFD166);
  static const Color _accentDark = Color(0xFFFFB347);
  static const Color _bgLight = Color(0xFFF7FBFC);
  static const Color _bgDark = Color(0xFF111418);
  static const Color _surfaceLight = Colors.white;
  static const Color _surfaceDark = Color(0xFF1B1F24);

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryLight,
        brightness: Brightness.light,
        primary: _primaryLight,
        secondary: _accentLight,
        surface: _surfaceLight,
      ),
      scaffoldBackgroundColor: _bgLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bgLight,
        foregroundColor: Color(0xFF1B1F24),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryLight,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      textTheme: _buildTextTheme(base.textTheme, Brightness.light),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryDark,
        brightness: Brightness.dark,
        primary: _primaryDark,
        secondary: _accentDark,
        surface: _surfaceDark,
      ),
      scaffoldBackgroundColor: _bgDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bgDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryDark,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      textTheme: _buildTextTheme(base.textTheme, Brightness.dark),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    final displayColor = brightness == Brightness.light
        ? const Color(0xFF1B1F24)
        : Colors.white;
    return base.copyWith(
      displayLarge: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: displayColor, height: 1.1),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: displayColor),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: displayColor),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: displayColor),
      bodyLarge: TextStyle(fontSize: 16, color: displayColor.withValues(alpha: 0.9)),
      bodyMedium: TextStyle(fontSize: 14, color: displayColor.withValues(alpha: 0.7)),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: displayColor),
    );
  }

  /// 流体填充色（PRD §2.2）
  static const Color fluidColor = Color(0xFF6AD7E0);
  static const Color fluidHighlight = Color(0xFFA3E4EB);
  static const Color fluidDark = Color(0xFF2C8A93);
}
