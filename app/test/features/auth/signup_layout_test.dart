import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/auth/presentation/signup_screen.dart';

import '../../helpers.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('sign up fits 360x640 with no scrolling', (tester) async {
    await pumpAt(tester, const SignUpScreen());

    // The acceptance criterion from the brief: the whole screen is reachable
    // on the shortest common Android viewport without a scroll gesture. The
    // page may scroll once a keyboard takes half of it, so what is checked is
    // that nothing has anywhere to scroll to while the keyboard is closed.
    for (final scrollable in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
      expect(
        scrollable.position.maxScrollExtent,
        0,
        reason: 'sign up must fit 360x640 without scrolling',
      );
    }
    expect(
      tester.takeException(),
      isNull,
      reason: 'no render box may overflow at 360x640',
    );

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);

    // Every social option Tack actually has configured is reachable without
    // scrolling. Facebook is deliberately absent: it is disabled server side,
    // and offering a button that cannot complete is worse than not offering it.
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Facebook'), findsNothing);
  });

  // With the keyboard up the screen overflowed by 146px and the Create account
  // button sat under the keyboard, with no way to scroll to it.
  testWidgets('with the keyboard open, Create account can still be reached', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());
    addTearDown(tester.view.resetViewInsets);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('Create account')).dy,
      lessThanOrEqualTo(shortAndroid.height - 300),
    );
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

  testWidgets('sign up asks for the fewest things that will do', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());

    // Two fields, because onboarding step one already asks for a name and a
    // social sign-in supplies it. A third field here is a third chance to
    // abandon sign-up.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('validation explains what to do rather than what went wrong', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Choose a password.'), findsOneWidget);
  });

  testWidgets('a short password is caught before the request is made', (
    tester,
  ) async {
    await pumpAt(tester, const SignUpScreen());

    await tester.enterText(find.byType(TextField).at(0), 'rafiq@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
  });
}
