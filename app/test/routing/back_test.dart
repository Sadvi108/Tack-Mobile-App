import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
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
}
