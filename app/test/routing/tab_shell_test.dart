import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';
import 'package:tack/routing/tab_bar.dart';

import '../helpers.dart';

/// The tab bar belongs to the router, not to a screen.
///
/// When every root screen drew its own bar, switching tabs was a page
/// transition: the bar slid off with the old screen while a copy slid in, and
/// whatever the student had scrolled to or typed was gone. These hold the
/// shell to the opposite: one bar, tabs kept alive, detail screens on top.
void main() {
  setUpAll(loadTackFonts);

  Future<GoRouter> pump(
    WidgetTester tester, {
    String at = '/home',
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final root = GlobalKey<NavigatorState>();
    Widget tab(String name) => Scaffold(
      body: Column(
        children: [
          Text('$name screen'),
          // Something a student would lose if the tab were rebuilt.
          SizedBox(width: 300, child: TextField(key: Key('$name field'))),
        ],
      ),
    );

    // Same shape as router.dart: five branches in TackTabs order, the
    // applications list inside Radar, the documents inside Toolkit, a single
    // application and the score screen on the root navigator.
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: at,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              TackTabShell(shell: shell, onSelected: onSelected),
          branches: [
            for (final t in TackTabs.all)
              StatefulShellBranch(
                routes: [
                  GoRoute(path: t.route, builder: (_, _) => tab(t.label)),
                  if (t == TackTabs.toolkit)
                    GoRoute(
                      path: '/vault',
                      builder: (context, _) => Scaffold(
                        body: Column(
                          children: [
                            const Text('Documents screen'),
                            // The real list's back arrow.
                            TextButton(
                              onPressed: () =>
                                  tackBack(context, fallback: Routes.toolkit),
                              child: const Text('documents back'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (t == TackTabs.radar)
                    GoRoute(
                      path: '/applications',
                      builder: (_, _) => tab('Applications'),
                      routes: [
                        GoRoute(
                          path: ':id',
                          parentNavigatorKey: root,
                          builder: (_, _) =>
                              const Scaffold(body: Text('one application')),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
        GoRoute(
          path: '/score',
          builder: (_, _) => const Scaffold(body: Text('score screen')),
        ),
        // Interview practice covers the bar, with the back fallbacks the
        // interview screen uses (C6): setup to the hub, review to setup.
        GoRoute(
          path: Routes.interview,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => tackBack(context, fallback: Routes.toolkit),
              child: const Text('interview setup'),
            ),
          ),
          routes: [
            GoRoute(
              path: 'review',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      tackBack(context, fallback: Routes.interview),
                  child: const Text('practise again'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: buildTackTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Finder inBar(String label) => find.descendant(
    of: find.byType(TackBottomNav),
    matching: find.text(label),
  );

  testWidgets('the bar sits at the bottom and leaves the tab its room', (
    tester,
  ) async {
    await pump(tester);

    // Scaffold offers its bottom bar the whole screen's height. A bar that
    // takes it covers the tab and floats its icons mid-screen.
    final bar = tester.getRect(find.byType(TackBottomNav));
    expect(bar.bottom, 800);
    expect(bar.height, lessThan(120));
    expect(tester.getRect(find.text('Home screen')).bottom, lessThan(bar.top));
  });

  testWidgets('the five tabs fit at the 360px minimum', (tester) async {
    await pump(tester);

    expect(find.byType(TackBottomNav), findsOneWidget);
    expect(find.text('Paths'), findsNothing, reason: 'paths is not a tab');
    expect(inBar('Toolkit'), findsOneWidget);
    expect(inBar('Vault'), findsNothing, reason: 'Vault became Toolkit');
    expect(TackTabs.all, hasLength(5));
    for (final t in TackTabs.all) {
      expect(
        tester.getSize(inBar(t.label)).width,
        lessThanOrEqualTo(360 / 5),
        reason: '${t.label} is too wide',
      );
    }
  });

  testWidgets('switching tabs keeps one bar where it is', (tester) async {
    await pump(tester);
    final before = tester.getTopLeft(find.byType(TackBottomNav));

    await tester.tap(inBar('Radar'));
    // Mid-switch is where the old bar used to slide out beside a new one.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TackBottomNav), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TackBottomNav)), before);
    await tester.pumpAndSettle();
    expect(find.text('Radar screen'), findsOneWidget);
  });

  testWidgets('a tab is where you left it', (tester) async {
    await pump(tester);

    await tester.tap(inBar('Radar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('Radar field')), 'Dhaka');

    await tester.tap(inBar('Toolkit'));
    await tester.pumpAndSettle();
    await tester.tap(inBar('Radar'));
    await tester.pumpAndSettle();

    expect(find.text('Dhaka'), findsOneWidget);
  });

  testWidgets('the applications list lights Radar, and Radar goes back to it', (
    tester,
  ) async {
    await pump(tester, at: '/applications');
    expect(find.text('Applications screen'), findsOneWidget);
    final radar = tester.widget<TackBottomNav>(find.byType(TackBottomNav));
    expect(radar.currentIndex, TackTabs.all.indexOf(TackTabs.radar));

    // Tapping the tab you are on returns to its first screen.
    await tester.tap(inBar('Radar'));
    await tester.pumpAndSettle();
    expect(find.text('Radar screen'), findsOneWidget);
  });

  testWidgets('a detail screen covers the bar and pops back to the tab', (
    tester,
  ) async {
    final router = await pump(tester, at: '/applications');

    router.push('/applications/abc');
    await tester.pumpAndSettle();
    expect(find.text('one application'), findsOneWidget);
    expect(find.byType(TackBottomNav), findsNothing);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Applications screen'), findsOneWidget);

    router.push('/score');
    await tester.pumpAndSettle();
    expect(find.text('score screen'), findsOneWidget);
    expect(find.byType(TackBottomNav), findsNothing);
  });

  // tab_selected is recorded from here. A re-tap of the tab you are on is not
  // a switch, so it is not reported.
  testWidgets('onSelected reports a switch, not a re-tap', (tester) async {
    final selected = <int>[];
    await pump(tester, onSelected: selected.add);

    await tester.tap(inBar('Home'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);

    await tester.tap(inBar('Radar'));
    await tester.pumpAndSettle();
    expect(selected, [TackTabs.all.indexOf(TackTabs.radar)]);

    await tester.tap(inBar('Radar'));
    await tester.pumpAndSettle();
    expect(selected, hasLength(1));
  });

  testWidgets(
    'the documents list lights Toolkit, and Toolkit goes back to it',
    (tester) async {
      await pump(tester, at: '/vault');
      expect(find.text('Documents screen'), findsOneWidget);
      final bar = tester.widget<TackBottomNav>(find.byType(TackBottomNav));
      expect(bar.currentIndex, TackTabs.all.indexOf(TackTabs.toolkit));
      expect(TackTabs.all.indexOf(TackTabs.toolkit), 3);

      // Tapping the tab you are on returns to the hub.
      await tester.tap(inBar('Toolkit'));
      await tester.pumpAndSettle();
      expect(find.text('Toolkit screen'), findsOneWidget);
    },
  );

  group('interview practice from the Toolkit', () {
    testWidgets('opened from the hub, it covers the bar and back returns', (
      tester,
    ) async {
      final router = await pump(tester, at: Routes.toolkit);
      router.push(Routes.interview);
      await tester.pumpAndSettle();
      expect(find.text('interview setup'), findsOneWidget);
      expect(find.byType(TackBottomNav), findsNothing);

      await tester.tap(find.text('interview setup'));
      await tester.pumpAndSettle();
      expect(find.text('Toolkit screen'), findsOneWidget);
      final bar = tester.widget<TackBottomNav>(find.byType(TackBottomNav));
      expect(bar.currentIndex, TackTabs.all.indexOf(TackTabs.toolkit));
    });

    testWidgets('a cold start on practise again backs out to setup, then '
        'the hub', (tester) async {
      await pump(tester, at: Routes.interviewReview);
      expect(find.text('practise again'), findsOneWidget);

      await tester.tap(find.text('practise again'));
      await tester.pumpAndSettle();
      expect(find.text('interview setup'), findsOneWidget);

      await tester.tap(find.text('interview setup'));
      await tester.pumpAndSettle();
      expect(find.text('Toolkit screen'), findsOneWidget);
      final bar = tester.widget<TackBottomNav>(find.byType(TackBottomNav));
      expect(bar.currentIndex, TackTabs.all.indexOf(TackTabs.toolkit));
    });

    testWidgets('the documents list backs out to the hub with nothing under '
        'it', (tester) async {
      final router = await pump(tester, at: Routes.vault);
      expect(router.canPop(), isFalse);
      await tester.tap(find.text('documents back'));
      await tester.pumpAndSettle();
      expect(find.text('Toolkit screen'), findsOneWidget);
      expect(
        tester.widget<TackBottomNav>(find.byType(TackBottomNav)).currentIndex,
        TackTabs.all.indexOf(TackTabs.toolkit),
      );
    });
  });
}
