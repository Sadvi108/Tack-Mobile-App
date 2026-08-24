import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Material is used only as a host. Tack draws its own controls, so the theme
/// mostly exists to stop Material's defaults leaking in.
ThemeData buildTackTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: TackColors.maroon,
    onPrimary: TackColors.white,
    secondary: TackColors.teal,
    onSecondary: TackColors.ink,
    tertiary: TackColors.amber,
    onTertiary: TackColors.ink,
    error: TackColors.danger,
    onError: TackColors.white,
    surface: TackColors.white,
    onSurface: TackColors.ink,
    surfaceContainerHighest: TackColors.sailWhite,
    outline: TackColors.line2,
    outlineVariant: TackColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TackColors.sailWhite,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      displayLarge: TackText.landingH1,
      headlineLarge: TackText.screenTitle,
      headlineMedium: TackText.sectionHeader,
      titleMedium: TackText.cardTitle,
      bodyLarge: TackText.bodyLarge,
      bodyMedium: TackText.body,
      bodySmall: TackText.meta,
      labelLarge: TackText.rowTitle,
      labelMedium: TackText.fieldLabel,
      labelSmall: TackText.monoLabel,
    ),
    dividerTheme: const DividerThemeData(
      color: TackColors.line, thickness: 1, space: 1,
    ),
    // Tack draws its own text fields; this only keeps stray Material inputs
    // from looking foreign if one slips in.
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: TackColors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: TackRadius.inputAll,
        borderSide: BorderSide(color: TackColors.line2, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TackRadius.inputAll,
        borderSide: BorderSide(color: TackColors.line2, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TackRadius.inputAll,
        borderSide: BorderSide(color: TackColors.maroon, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TackRadius.inputAll,
        borderSide: BorderSide(color: TackColors.danger, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TackColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: TackRadius.sheetTop),
      showDragHandle: false,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

const tackSystemOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: TackColors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
);

const tackSystemOverlayOnMaroon = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: TackColors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
);
