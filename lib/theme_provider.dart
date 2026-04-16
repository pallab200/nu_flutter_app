import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Theme Notifier ──────────────────────────────────────────────────────────
/// Manages app-wide theme (light / dark) and persists the preference.
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier._();

  static final ThemeNotifier instance = ThemeNotifier._();
  static const _key = 'theme_mode_v1';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  /// Call once at startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
    }
    _updateSystemUI();
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    _updateSystemUI();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, isDark ? 'dark' : 'light');
  }

  void _updateSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }
}

// ─── Design Tokens ───────────────────────────────────────────────────────────
class AppColors {
  // Common accent / brand colors
  static const primary = Color(0xFF1565C0);
  static const gold = Color(0xFFFFB300);
  static const heroTop = Color(0xFF0D47A1);
  static const heroBottom = Color(0xFF1565C0);

  // ── Light mode ──
  static const lightSurface = Color(0xFFF4F6FB);
  static const lightCard = Colors.white;
  static const lightTextPrimary = Color(0xFF0D1B2A);
  static const lightTextSecondary = Color(0xFF64748B);
  static const lightTextTertiary = Color(0xFF94A3B8);
  static const lightBorder = Color(0xFFE2E8F0);
  static const lightDivider = Color(0xFFF3F4F6);
  static const lightCardShadow = Color(0x1A000000);
  static const lightSubtleBg = Color(0xFFF8FAFC);
  static const lightSearchBg = Colors.white;
  static const lightNoticeCircle = Color(0xFFE1EFFE);
  static const lightNoticeCircleText = Color(0xFF3D78B8);
  static const lightNoticeTitleText = Color(0xFF334155);
  static const lightNoticeDateText = Color(0xFF6B7280);
  static const lightAccentText = Color(0xFF3D78B8);
  static const lightGradientTop = Color(0xFFEFF8FF);
  static const lightGradientBottom = Color(0xFFF8FAFC);
  static const lightInputBg = Color(0xFFF8FAFC);
  static const lightCacheBg = Color(0xFFFFFBEB);
  static const lightCacheBorder = Color(0xFFFDE68A);
  static const lightCacheText = Color(0xFF92400E);

  // ── Dark mode ──
  static const darkSurface = Color(0xFF0F1724);
  static const darkCard = Color(0xFF1A2332);
  static const darkTextPrimary = Color(0xFFE2E8F0);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkTextTertiary = Color(0xFF64748B);
  static const darkBorder = Color(0xFF2D3B4E);
  static const darkDivider = Color(0xFF253245);
  static const darkCardShadow = Color(0x40000000);
  static const darkSubtleBg = Color(0xFF162030);
  static const darkSearchBg = Color(0xFF1A2332);
  static const darkNoticeCircle = Color(0xFF1A3A5C);
  static const darkNoticeCircleText = Color(0xFF60A5FA);
  static const darkNoticeTitleText = Color(0xFFCBD5E1);
  static const darkNoticeDateText = Color(0xFF94A3B8);
  static const darkAccentText = Color(0xFF60A5FA);
  static const darkGradientTop = Color(0xFF0F1724);
  static const darkGradientBottom = Color(0xFF162030);
  static const darkInputBg = Color(0xFF1A2332);
  static const darkCacheBg = Color(0xFF422006);
  static const darkCacheBorder = Color(0xFF854D0E);
  static const darkCacheText = Color(0xFFFDE68A);

  // ── Helpers ──
  static Color surface(bool isDark) => isDark ? darkSurface : lightSurface;
  static Color card(bool isDark) => isDark ? darkCard : lightCard;
  static Color textPrimary(bool isDark) =>
      isDark ? darkTextPrimary : lightTextPrimary;
  static Color textSecondary(bool isDark) =>
      isDark ? darkTextSecondary : lightTextSecondary;
  static Color textTertiary(bool isDark) =>
      isDark ? darkTextTertiary : lightTextTertiary;
  static Color border(bool isDark) => isDark ? darkBorder : lightBorder;
  static Color divider(bool isDark) => isDark ? darkDivider : lightDivider;
  static Color cardShadow(bool isDark) =>
      isDark ? darkCardShadow : lightCardShadow;
  static Color subtleBg(bool isDark) => isDark ? darkSubtleBg : lightSubtleBg;
  static Color searchBg(bool isDark) => isDark ? darkSearchBg : lightSearchBg;
  static Color noticeCircle(bool isDark) =>
      isDark ? darkNoticeCircle : lightNoticeCircle;
  static Color noticeCircleText(bool isDark) =>
      isDark ? darkNoticeCircleText : lightNoticeCircleText;
  static Color noticeTitleText(bool isDark) =>
      isDark ? darkNoticeTitleText : lightNoticeTitleText;
  static Color noticeDateText(bool isDark) =>
      isDark ? darkNoticeDateText : lightNoticeDateText;
  static Color accentText(bool isDark) =>
      isDark ? darkAccentText : lightAccentText;
  static Color gradientTop(bool isDark) =>
      isDark ? darkGradientTop : lightGradientTop;
  static Color gradientBottom(bool isDark) =>
      isDark ? darkGradientBottom : lightGradientBottom;
  static Color inputBg(bool isDark) => isDark ? darkInputBg : lightInputBg;
  static Color cacheBg(bool isDark) => isDark ? darkCacheBg : lightCacheBg;
  static Color cacheBorder(bool isDark) =>
      isDark ? darkCacheBorder : lightCacheBorder;
  static Color cacheText(bool isDark) =>
      isDark ? darkCacheText : lightCacheText;
}

// ─── Theme Definitions ───────────────────────────────────────────────────────
ThemeData buildLightTheme() => ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.lightSurface,
      useMaterial3: true,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
    );

ThemeData buildDarkTheme() => ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.darkSurface,
      useMaterial3: true,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkCard,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
    );
