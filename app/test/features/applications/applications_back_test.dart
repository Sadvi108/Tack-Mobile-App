import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/applications/data/application_repository.dart';
import 'package:tack/features/applications/presentation/applications_screen.dart';
import 'package:tack/routing/router.dart';

import '../../helpers.dart';

/// The standalone list is reached from notifications and the score
/// breakdown, often with nothing under it. Its back arrow used to be missing
/// altogether; now it returns to whoever opened it, or to Radar.
void main() {
  setUpAll(loadTackFonts);

  Future<GoRouter> pump(WidgetTester tester, {required String at}) async {
    tester.view.physicalSize = shortAndroid;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: Routes.radar,
          builder: (_, _) => const Scaffold(body: Text('radar page')),
        ),
        GoRoute(
          path: Routes.score,
          builder: (_, _) => const Scaffold(body: Text('score page')),
        ),
        GoRoute(
          path: Routes.applications,
          builder: (_, _) => const ApplicationsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          applicationCountsProvider.overrideWith(
            (ref) async => ApplicationCounts.empty,
          ),
          applicationsProvider.overrideWith((ref, status) async => const []),
        ],
        child: MaterialApp.router(
          theme: buildTackTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('with nothing under it, back lands on Radar', (tester) async {
    await pump(tester, at: Routes.applications);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('radar page'), findsOneWidget);
  });

  testWidgets('opened from the score, back returns there', (tester) async {
    final router = await pump(tester, at: Routes.score);
    router.push(Routes.applications);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('score page'), findsOneWidget);
  });
}
