import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/auth/presentation/signup_screen.dart';

import '../../helpers.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('sign up fits 360x640 with no scrolling', (tester) async {
    await pumpAt(tester, const SignUpScreen());

    // The acceptance criterion from the brief: the whole screen is reachable
    // on the shortest common Android viewport without a scroll gesture.
    // Text fields carry their own internal Scrollable, so this checks for a
    // page-level scroll view specifically.
    expect(
      find.byType(SingleChildScrollView),
      findsNothing,
      reason: 'sign up must not introduce a page scroll view',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'no render box may overflow at 360x640',
    );

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('sign up still fits with the largest supported text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAt(tester, const SignUpScreen());
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tappable control clears the 44px minimum', (tester) async {
    await pumpAt(tester, const SignUpScreen());

    for (final finder in [
      find.text('Create account'),
      find.text('Continue with Google'),
    ]) {
      final size = tester.getSize(
        find.ancestor(of: finder, matching: find.byType(Container)).first,
      );
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: 'tap targets must be at least 44px tall',
      );
    }
  });

  testWidgets('validation explains what to do rather than what went wrong', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Choose a password.'), findsOneWidget);
  });

  testWidgets('a short password is caught before the request is made', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());

    await tester.enterText(find.byType(TextField).at(0), 'Rafiq Hossain');
    await tester.enterText(find.byType(TextField).at(1), 'rafiq@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
  });
}
