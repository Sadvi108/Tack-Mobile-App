// Renders the dashboard to PNG files, for looking at.
//
// Deliberately not named *_test.dart, so `flutter test` does not run it. It is
// a design-review tool, not a check — nothing here asserts anything.
//
//   flutter test test/dashboard_shots.dart
//
// Writes into build/shots/. The payload is a real `dashboard_feed()` response
// captured from a seeded demo student (tool/seed_dashboard_demo.js), so what
// comes out is what the screen does with real data rather than with whatever a
// fixture author imagined.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/dashboard/data/dashboard_repository.dart';
import 'package:tack/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tack/features/profile/data/profile.dart';

import 'helpers.dart';

const _out = 'build/shots';

Future<void> render(
  WidgetTester tester,
  DashboardFeed feed,
  String name,
  Size size, {
  List<double> panels = const [],
  Brightness brightness = Brightness.light,
}) async {
  TackBrightness.set(brightness);
  addTearDown(() => TackBrightness.set(Brightness.light));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
      for (final r in [
        '/home',
        '/roadmap',
        '/applications',
        '/vault',
        '/profile',
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
      overrides: [
        localDbProvider.overrideWith((ref) {
          final db = LocalDb(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
        dashboardFeedProvider.overrideWith((ref) async => feed),
      ],
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

  if (panels.isEmpty) {
    await capture(name);
    return;
  }

  // Scroll the real list rather than cropping a tall render: what comes out is
  // what the phone shows, bottom bar included.
  final list = find.byType(Scrollable).first;
  var at = 0.0;
  for (var i = 0; i < panels.length; i++) {
    final target = panels[i];
    if (target > at) {
      await tester.drag(list, Offset(0, -(target - at)), warnIfMissed: false);
      await tester.pumpAndSettle();
      at = target;
    }
    await capture('$name-${i + 1}');
  }
}

void main() {
  setUpAll(loadTackFonts);

  final raw =
      jsonDecode(
            File('test/fixtures/dashboard_feed_demo.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  testWidgets('the whole dashboard, one phone screen at a time', (
    tester,
  ) async {
    await render(
      tester,
      DashboardFeed.fromJson(raw),
      'launch',
      const Size(390, 844),
      panels: const [0, 620, 1240, 1860, 2480],
    );
  });

  testWidgets('and at the 360px floor, where it is tightest', (tester) async {
    await render(
      tester,
      DashboardFeed.fromJson(raw),
      'launch-360',
      const Size(360, 640),
      panels: const [0, 520, 1040, 1560, 2080],
    );
  });

  testWidgets('the whole dashboard again, in the dark', (tester) async {
    await render(
      tester,
      DashboardFeed.fromJson(raw),
      'launch-dark',
      const Size(390, 844),
      panels: const [0, 620, 1240, 1860, 2480],
      brightness: Brightness.dark,
    );
  });

  for (final mode in [YearMode.explore, YearMode.build, YearMode.prove]) {
    testWidgets('the same student in ${mode.name} mode', (tester) async {
      final patched = Map<String, dynamic>.from(raw)
        ..['profile'] = {
          ...(raw['profile'] as Map).cast<String, dynamic>(),
          'mode': mode.name,
          'year_of_study': switch (mode) {
            YearMode.explore => 1,
            YearMode.build => 2,
            _ => 3,
          },
        };
      await render(
        tester,
        DashboardFeed.fromJson(patched),
        mode.name,
        const Size(390, 844),
        panels: const [0, 620, 1240, 1860],
      );
    });
  }
}
