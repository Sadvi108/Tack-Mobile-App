import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';

const _out = 'build/shots';

/// Renders any screen to PNG panels. Design-review only; asserts nothing.
Future<void> shoot(
  WidgetTester tester,
  Widget screen,
  String name,
  Size size, {
  List<Override> overrides = const [],
  List<double> panels = const [0],
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      for (final r in [
        '/home',
        '/roadmap',
        '/radar',
        '/vault',
        '/profile',
        '/applications',
        '/paths',
        '/score',
        '/notifications',
      ])
        GoRoute(path: r, builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp.router(
          theme: buildTackTheme(brightness),
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  Future<void> capture(String file) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$file.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('  wrote $_out/$file.png');
    });
  }

  final scrollable = find.byType(Scrollable);
  var at = 0.0;
  for (var i = 0; i < panels.length; i++) {
    if (panels[i] > at && scrollable.evaluate().isNotEmpty) {
      await tester.drag(
        scrollable.last,
        Offset(0, -(panels[i] - at)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      at = panels[i];
    }
    await capture(panels.length == 1 ? name : '$name-${i + 1}');
  }
}
