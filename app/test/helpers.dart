import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';

/// Loads the fonts the app actually ships.
///
/// Widget tests otherwise render with a placeholder font whose every glyph is
/// a square em box, which makes text far wider and taller than it really is.
/// A "fits 360x640" assertion is only meaningful against the real metrics.
Future<void> loadTackFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const families = {
    'Inter': ['Inter-Regular', 'Inter-Medium', 'Inter-SemiBold'],
    'Outfit': ['Outfit-Medium', 'Outfit-SemiBold'],
    'IBMPlexMono': ['IBMPlexMono-Medium', 'IBMPlexMono-SemiBold'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final bytes = await File('assets/fonts/$file.ttf').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// The shortest common Android viewport the design is measured against.
const shortAndroid = Size(360, 640);

/// Pumps a widget at an exact device size with the real theme, so a layout
/// assertion means something.
Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = shortAndroid,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      GoRoute(path: '/login', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/signup', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(theme: buildTackTheme(), routerConfig: router),
    ),
  );
  await tester.pump();
}

/// True when any render box in the tree reported an overflow.
bool hasOverflow(WidgetTester tester) =>
    tester.takeException().toString().contains('overflow');
