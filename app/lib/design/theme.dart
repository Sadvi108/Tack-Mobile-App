import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Material is used only as a host. Tack draws its own controls, so the theme
/// mostly exists to stop Material's defaults leaking in.
ThemeData buildTackTheme([Brightness brightness = Brightness.light]) {
  // The palette has to be switched before the scheme reads any of it: every
  // TackColors member resolves against TackBrightness, so building a dark
  // theme while the holder still says light would produce a light scheme.
  TackBrightness.set(brightness);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: TackColors.maroon,
    onPrimary: TackColors.onBrand,
    secondary: TackColors.teal,
    onSecondary: TackColors.ink,
    tertiary: TackColors.amber,
    onTertiary: TackColors.ink,
    error: TackColors.danger,
    onError: TackColors.onBrand,
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
    textTheme: TextTheme(
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
    dividerTheme: DividerThemeData(
      color: TackColors.line,
      thickness: 1,
      space: 1,
    ),
    // Tack draws its own text fields; this only keeps stray Material inputs
    // from looking foreign if one slips in.
    inputDecorationTheme: InputDecorationTheme(
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
        borderSide: BorderSide(color: TackColors.maroonText, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TackRadius.inputAll,
        borderSide: BorderSide(color: TackColors.danger, width: 1.5),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: TackColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: TackRadius.sheetTop),
      showDragHandle: false,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// The status and navigation bars follow the palette, so a dark app does not
/// sit under black status text on a black ground.
SystemUiOverlayStyle get tackSystemOverlay => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: TackBrightness.isDark
      ? Brightness.light
      : Brightness.dark,
  statusBarBrightness: TackBrightness.isDark
      ? Brightness.dark
      : Brightness.light,
  systemNavigationBarColor: TackColors.white,
  systemNavigationBarIconBrightness: TackBrightness.isDark
      ? Brightness.light
      : Brightness.dark,
);

/// A maroon header is dark in both palettes, so its status icons are always
/// light — but the navigation bar still follows the page underneath it.
SystemUiOverlayStyle get tackSystemOverlayOnMaroon => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: TackColors.white,
  systemNavigationBarIconBrightness: TackBrightness.isDark
      ? Brightness.light
      : Brightness.dark,
);
