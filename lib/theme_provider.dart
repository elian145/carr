import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
}

/// Brand accent; [ColorScheme.fromSeed] builds surfaces; we override ink colors for stronger contrast.
class AppThemes {
  static const Color _brandOrange = Color(0xFFFF6B00);
  static const Color _brandSecondary = Color(0xFFFF8C42);

  /// Light mode: full-bleed scaffold / home body (pure white).
  static const Color lightAppBackground = Color(0xFFFFFFFF);

  /// Dark home shell gradient (legacy pages).
  static const List<Color> darkShellGradientColors = [
    Color(0xFF0F1115),
    Color(0xFF131722),
    Color(0xFF0F1115),
  ];

  /// Mid tone of [darkShellGradientColors] — dark home “base” (accent text on bright listing body).
  static const Color darkHomeShellBackground = Color(0xFF131722);

  /// Page background: dark gradient or light white shell.
  static BoxDecoration shellBackgroundDecoration(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: darkShellGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    }
    return const BoxDecoration(color: lightAppBackground);
  }

  /// Bottom bar colors for legacy CARZO tabs.
  static ({Color backgroundColor, Color unselectedItemColor}) bottomNavChrome(
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    return (
      backgroundColor: isDark ? const Color(0xDE000000) : lightAppBackground,
      unselectedItemColor: isDark ? const Color(0xB3FFFFFF) : const Color(0xFF757575),
    );
  }

  /// Primary text on light surfaces (~near-black on white).
  static const Color _lightInk = Color(0xFF0A0A0A);
  /// Secondary / supporting text — still dark enough to read clearly on white cards.
  static const Color _lightInkMuted = Color(0xFF3A3A3A);

  /// Primary text on dark surfaces.
  static const Color _darkInk = Color(0xFFF7F7F7);
  /// Secondary text — clearly lighter than card fill, not dim grey.
  static const Color _darkInkMuted = Color(0xFFD8D8D8);

  static ThemeData _withContrastTextTheme(ThemeData base, ColorScheme scheme) {
    final t = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return base.copyWith(
      textTheme: t.copyWith(
        bodySmall: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        bodyMedium: t.bodyMedium?.copyWith(color: scheme.onSurface),
        bodyLarge: t.bodyLarge?.copyWith(color: scheme.onSurface),
        labelSmall: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        labelMedium: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelLarge: t.labelLarge?.copyWith(color: scheme.onSurface),
        titleSmall: t.titleSmall?.copyWith(color: scheme.onSurface),
        titleMedium: t.titleMedium?.copyWith(color: scheme.onSurface),
        titleLarge: t.titleLarge?.copyWith(color: scheme.onSurface),
        headlineSmall: t.headlineSmall?.copyWith(color: scheme.onSurface),
        headlineMedium: t.headlineMedium?.copyWith(color: scheme.onSurface),
        headlineLarge: t.headlineLarge?.copyWith(color: scheme.onSurface),
      ),
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brandOrange,
      brightness: Brightness.light,
    ).copyWith(
      primary: _brandOrange,
      onPrimary: Colors.white,
      secondary: _brandSecondary,
      onSecondary: Colors.white,
      // Surfaces match the home shell: white. Slightly stronger containers for inputs/chips.
      surface: lightAppBackground,
      onSurface: _lightInk,
      onSurfaceVariant: _lightInkMuted,
      surfaceContainerLowest: lightAppBackground,
      surfaceContainerLow: lightAppBackground,
      surfaceContainer: const Color(0xFFF3F3F3),
      surfaceContainerHigh: const Color(0xFFEBEBEB),
      surfaceContainerHighest: const Color(0xFFE0E0E0),
      outline: const Color(0xFF6B6B6B),
      outlineVariant: const Color(0xFFCACACA),
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightAppBackground,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.iOS: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.linux: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.macOS: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.windows: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppNoTransitionsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return _withContrastTextTheme(base, scheme);
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brandOrange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _brandOrange,
      onPrimary: Colors.white,
      secondary: _brandSecondary,
      onSecondary: Colors.white,
      surface: const Color(0xFF1E1E1E),
      onSurface: _darkInk,
      onSurfaceVariant: _darkInkMuted,
      outline: const Color(0xFF9E9E9E),
      outlineVariant: const Color(0xFF5C5C5C),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.iOS: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.linux: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.macOS: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.windows: AppNoTransitionsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppNoTransitionsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return _withContrastTextTheme(base, scheme);
  }
}

class AppNoTransitionsPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppNoTransitionsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
