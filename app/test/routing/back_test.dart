import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/routing/router.dart';

/// A back arrow that does nothing is worse than no back arrow: the student
/// presses it, nothing happens, and they conclude the app is broken. That is
/// what the interview screen did, because it was only ever reachable by deep
/// link and `context.pop()` has nothing to pop when there is no history.
void main() {
  Future<GoRouter> pump(WidgetTester tester, {required String at}) async {
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
        ),
        GoRoute(
          path: '/vault',
          builder: (_, _) => const Scaffold(body: Text('vault')),
        ),
        GoRoute(
          path: '/deep',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => tackBack(context),
                child: const Text('back'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/deep-to-vault',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => tackBack(context, fallback: '/vault'),
                child: const Text('back'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('with no history at all, back still reaches the dashboard', (
    tester,
  ) async {
    await pump(tester, at: '/deep');
    expect(find.text('back'), findsOneWidget);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    expect(
      find.text('dashboard'),
      findsOneWidget,
      reason: 'a cold start on a route leaves nothing to pop',
    );
  });

  testWidgets('a screen can name where back should land', (tester) async {
    await pump(tester, at: '/deep-to-vault');
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('vault'), findsOneWidget);
  });

  testWidgets('with history, back returns to where you came from', (
    tester,
  ) async {
    final router = await pump(tester, at: '/vault');
    router.push('/deep');
    await tester.pumpAndSettle();

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    expect(
      find.text('vault'),
      findsOneWidget,
      reason: 'the fallback must not override real history',
    );
  });

  // One helper decides go or push for every cross-screen link. A tab is gone
  // to, so the bar switches and nothing piles up behind it; anything else
  // covers the bar and is pushed, so back returns to whoever opened it.
  group('tackOpen', () {
    Widget opener(String label, String location) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              TextButton(
                onPressed: () => tackOpen(context, location),
                child: Text('open $location'),
              ),
            ],
          ),
        ),
      ),
    );

    Future<GoRouter> pumpShell(
      WidgetTester tester, {
      required String to,
    }) async {
      final router = GoRouter(
        initialLocation: Routes.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => shell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: Routes.home,
                    builder: (_, _) => opener('dashboard', to),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: Routes.roadmap,
                    builder: (_, _) => opener('roadmap', to),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: Routes.analyser,
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => tackBack(context),
                  child: const Text('analyser back'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    String path(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.path;

    testWidgets('a tab location switches tab without stacking', (tester) async {
      final router = await pumpShell(tester, to: Routes.roadmap);

      await tester.tap(find.text('open ${Routes.roadmap}').first);
      await tester.pumpAndSettle();
      expect(path(router), Routes.roadmap);
      expect(find.text('roadmap'), findsOneWidget);

      // Opening it again from the tab itself still leaves nothing behind.
      await tester.tap(find.text('open ${Routes.roadmap}').last);
      await tester.pumpAndSettle();
      expect(path(router), Routes.roadmap);
      expect(router.canPop(), isFalse);
    });

    testWidgets('a cover route is pushed, and back returns to the opener', (
      tester,
    ) async {
      final router = await pumpShell(tester, to: Routes.analyser);

      await tester.tap(find.text('open ${Routes.analyser}'));
      await tester.pumpAndSettle();
      // Pushed: the screen is on top of the opener, not in place of it.
      expect(find.text('analyser back'), findsOneWidget);
      expect(router.canPop(), isTrue);

      await tester.tap(find.text('analyser back'));
      await tester.pumpAndSettle();
      expect(path(router), Routes.home);
      expect(find.text('dashboard'), findsOneWidget);
    });

    test('a tab location is matched on its path alone', () {
      expect(Routes.isTabLocation('${Routes.home}?from=coach'), isTrue);
      expect(Routes.isTabLocation(Routes.toolkit), isTrue);
      expect(Routes.isTabLocation(Routes.vault), isTrue);
      expect(Routes.isTabLocation(Routes.application('a1')), isFalse);
      expect(Routes.isTabLocation(Routes.interviewReview), isFalse);
      expect(Routes.isTabLocation(Routes.cvCheckFor('d1')), isFalse);
    });
  });
}
