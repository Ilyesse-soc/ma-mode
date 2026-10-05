import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Design system — direction visuelle maquette : sombre premium, mode/lifestyle.
class AppColors {
  static const Color background = Color(0xFF0B0B0C);
  static const Color surface = Color(0xFF191A1B);
  static const Color surfaceElevated = Color(0xFF232426);
  static const Color border = Color(0xFF29292D);
  static const Color primaryText = Color(0xFFF5F2EA);
  static const Color secondaryText = Color(0xFFA7A5A0);
  static const Color accentCream = Color(0xFFEDE2CE);
  static const Color accentDark = Color(0xFF242326);
  static const Color success = Color(0xFF5DAE78);
  static const Color danger = Color(0xFFC95858);

  // Light mode: inversion douce de la même direction.
  static const Color lightBackground = Color(0xFFF5F2EA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFEDE8DC);
  static const Color lightBorder = Color(0xFFDDD5C6);
  static const Color lightText = Color(0xFF1C1B1F);
  static const Color lightSecondaryText = Color(0xFF6E6A62);
}

class AppTheme {
  static const double spacingXs = 4;
  static const double spacingS = 8;
  static const double spacingM = 16;
  static const double spacingL = 24;
  static const double spacingXl = 32;

  static const double radiusM = 10;
  static const double radiusL = 14;
  static const double radiusPill = 28;

  /// iOS: SF Pro (système). Android/autres: Inter.
  static TextTheme _textTheme(Brightness brightness, Color color) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final themed = (!kIsWeb && Platform.isIOS)
        ? base
        : base.apply(fontFamily: 'Inter');
    return themed
        .apply(bodyColor: color, displayColor: color)
        .copyWith(
          displayLarge: themed.displayLarge?.copyWith(
            fontSize: 48,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: color,
          ),
          displayMedium: themed.displayMedium?.copyWith(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            color: color,
          ),
          displaySmall: themed.displaySmall?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
            color: color,
          ),
          headlineLarge: themed.headlineLarge?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: color,
          ),
          headlineMedium: themed.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: color,
          ),
          headlineSmall: themed.headlineSmall?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: color,
          ),
          titleLarge: themed.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          titleMedium: themed.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          titleSmall: themed.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          bodyLarge: themed.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.5,
            color: color,
          ),
          bodyMedium: themed.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: color,
          ),
          bodySmall: themed.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.4,
            color: color,
          ),
          labelLarge: themed.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: color,
          ),
          labelMedium: themed.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          labelSmall: themed.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: color,
          ),
        );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: AppColors.background,
      onSurface: AppColors.primaryText,
      surfaceContainerHighest: AppColors.surfaceElevated,
      primary: AppColors.accentCream,
      onPrimary: AppColors.accentDark,
      secondary: AppColors.secondaryText,
      onSecondary: AppColors.primaryText,
      error: AppColors.danger,
      outline: AppColors.border,
    );
    return _build(
      scheme,
      AppColors.background,
      AppColors.surface,
      AppColors.surfaceElevated,
      AppColors.border,
      AppColors.primaryText,
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      surface: AppColors.lightBackground,
      onSurface: AppColors.lightText,
      surfaceContainerHighest: AppColors.lightSurfaceElevated,
      primary: AppColors.accentDark,
      onPrimary: AppColors.accentCream,
      secondary: AppColors.lightSecondaryText,
      onSecondary: AppColors.lightText,
      error: AppColors.danger,
      outline: AppColors.lightBorder,
    );
    return _build(
      scheme,
      AppColors.lightBackground,
      AppColors.lightSurface,
      AppColors.lightSurfaceElevated,
      AppColors.lightBorder,
      AppColors.lightText,
    );
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color background,
    Color surface,
    Color surfaceElevated,
    Color border,
    Color text,
  ) {
    final secondaryText = scheme.secondary;
    final textTheme = _textTheme(scheme.brightness, text);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
          side: BorderSide(color: border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: surfaceElevated,
        selectedColor: scheme.primary,
        labelStyle: textTheme.bodyMedium?.copyWith(color: text),
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onPrimary,
        ),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        labelStyle: TextStyle(color: secondaryText),
        hintStyle: TextStyle(color: secondaryText),
        prefixIconColor: secondaryText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        dragHandleColor: secondaryText,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusL)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: secondaryText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : secondaryText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : surfaceElevated,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: surfaceElevated,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? scheme.primary
                : surfaceElevated,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : text,
          ),
          side: WidgetStateProperty.all(BorderSide(color: border)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Transitions courtes 200–350 ms comme sur la maquette.
class AppDurations {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 350);
}
