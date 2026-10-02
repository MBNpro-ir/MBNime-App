import 'package:flutter/material.dart';

abstract final class AnimeColors {
  static const background = Color(0xFF080A0F);
  static const surface = Color(0xFF11141C);
  static const surfaceHigh = Color(0xFF1A1E29);
  static const orange = Color(0xFFFF7A1A);
  static const coral = Color(0xFFFF4F6D);
  static const violet = Color(0xFF8D6BFF);
  static const cyan = Color(0xFF3FD8D4);
  static const text = Color(0xFFF7F7FA);
  static const muted = Color(0xFFA5A9B6);
  // Player accent is intentionally red (hentai / MBNime player identity),
  // while the rest of the app keeps the orange brand.
  static const playerAccent = Color(0xFFEF4444);
}

abstract final class AnimeTheme {
  static ThemeData get dark => buildTheme();

  static ThemeData buildTheme({
    bool highContrast = false,
    VisualDensity visualDensity = VisualDensity.standard,
    bool reduceMotion = false,
    bool boldText = false,
    Color? focusColor,
    Color? hoverColor,
  }) {
    final baseBg = highContrast ? Colors.black : AnimeColors.background;
    final baseSurface = highContrast
        ? const Color(0xFF0C0E14)
        : AnimeColors.surface;
    final baseSurfaceHigh = highContrast
        ? const Color(0xFF171B24)
        : AnimeColors.surfaceHigh;
    final primaryColor = highContrast
        ? const Color(0xFFFF9447)
        : AnimeColors.orange;
    final outlineColor = highContrast
        ? Colors.white70
        : const Color(0xFF353A49);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: baseBg,
      visualDensity: visualDensity,
      focusColor: focusColor,
      hoverColor: hoverColor,
      cardTheme: CardThemeData(
        color: baseSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: baseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: highContrast ? Colors.white60 : Colors.white12,
        thickness: highContrast ? 1.5 : 1.0,
      ),
      sliderTheme: SliderThemeData(
        // Flutter 3.44 still defaults to the legacy M3 slider. Explicit opt-in
        // follows Flutter's updated-material-3-slider migration guide.
        // ignore: deprecated_member_use
        year2023: false,
        trackHeight: 10,
        trackGap: 6,
        thumbSize: const WidgetStatePropertyAll(Size(4, 36)),
        activeTrackColor: primaryColor,
        secondaryActiveTrackColor: primaryColor.withValues(alpha: .35),
        inactiveTrackColor: highContrast ? Colors.white30 : Colors.white12,
        showValueIndicator: ShowValueIndicator.always,
      ),
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                TargetPlatform.windows: _MbnimePageTransitionsBuilder(),
                TargetPlatform.linux: _MbnimePageTransitionsBuilder(),
                TargetPlatform.macOS: _MbnimePageTransitionsBuilder(),
              },
            ),
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        onPrimary: const Color(0xFF241000),
        secondary: AnimeColors.violet,
        tertiary: AnimeColors.cyan,
        surface: baseSurface,
        onSurface: highContrast ? Colors.white : AnimeColors.text,
        surfaceContainer: baseSurface,
        surfaceContainerHigh: baseSurfaceHigh,
        outline: outlineColor,
        error: AnimeColors.coral,
      ),
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 32,
          height: 1.25,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.4,
          fontWeight: boldText ? FontWeight.w800 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: boldText ? FontWeight.w800 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.7,
          fontWeight: boldText ? FontWeight.w600 : FontWeight.normal,
          color: highContrast ? Colors.white : null,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          height: 1.65,
          fontWeight: boldText ? FontWeight.w600 : FontWeight.normal,
          color: highContrast ? Colors.white.withValues(alpha: 0.92) : null,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: baseSurfaceHigh.withValues(alpha: .88),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: highContrast ? Colors.white70 : const Color(0xFF292E3B),
            width: highContrast ? 1.5 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: primaryColor,
            width: highContrast ? 2.0 : 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: highContrast ? Colors.white60 : AnimeColors.muted,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: baseSurface.withValues(alpha: .96),
        indicatorColor: primaryColor.withValues(alpha: .18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : (highContrast ? Colors.white70 : AnimeColors.muted),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          animationDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.2)
              : BorderSide.none,
          textStyle: TextStyle(
            fontFamily: 'Vazirmatn',
            fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          overlayColor: WidgetStateProperty.all(
            primaryColor.withValues(alpha: .14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: baseSurfaceHigh,
        selectedColor: primaryColor.withValues(alpha: .2),
        side: BorderSide(
          color: highContrast ? Colors.white70 : const Color(0xFF2A2F3C),
          width: highContrast ? 1.5 : 1.0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: boldText ? FontWeight.w700 : FontWeight.normal,
          color: AnimeColors.text,
        ),
        secondaryLabelStyle: const TextStyle(color: AnimeColors.text),
        checkmarkColor: AnimeColors.text,
      ),
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

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

class _MbnimePageTransitionsBuilder extends PageTransitionsBuilder {
  const _MbnimePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData hentaiTheme(ThemeData base) {
  const red = AnimeColors.playerAccent;
  return base.copyWith(
    primaryColor: red,
    colorScheme: base.colorScheme.copyWith(
      primary: red,
      secondary: red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      primaryContainer: red.withValues(alpha: .2),
      secondaryContainer: red.withValues(alpha: .2),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      focusedBorder: base.inputDecorationTheme.focusedBorder?.copyWith(
        borderSide: const BorderSide(color: red, width: 1.4),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: red,
      selectionColor: red.withValues(alpha: .3),
      selectionHandleColor: red,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(color: red),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: red,
      thumbColor: red,
      overlayColor: red.withValues(alpha: .15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: red,
        foregroundColor: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: red,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: red),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: red),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: red.withValues(alpha: .2),
      secondarySelectedColor: red.withValues(alpha: .2),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: red),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      indicatorColor: red,
      labelColor: red,
    ),
  );
}
