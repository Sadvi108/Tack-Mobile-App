import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/auth/presentation/login_screen.dart';

import '../../helpers.dart';

/// The same promise sign-up keeps: with the keyboard open the form scrolls
/// rather than overflowing, so "Log in" is never stuck under the keyboard.
void main() {
  setUpAll(loadTackFonts);

  Future<void> keyboardOpen(WidgetTester tester) async {
    await pumpAt(tester, const LoginScreen());
    addTearDown(tester.view.resetViewInsets);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');

    final button = find.widgetWithText(Semantics, 'Log in').first;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(button).dy,
      lessThanOrEqualTo(shortAndroid.height - 300),
    );
  }

  testWidgets('with the keyboard open, Log in can still be reached', (
    tester,
  ) async {
    await keyboardOpen(tester);
  });

  testWidgets('and at the largest supported text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await keyboardOpen(tester);
  });

  testWidgets('with the keyboard closed, it still fits 360x640', (
    tester,
  ) async {
    await pumpAt(tester, const LoginScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
