import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/features/coach/data/coach_repository.dart';
import 'package:tack/features/coach/presentation/coach_screen.dart';

import '../../helpers.dart';

ChatMessage msg(String role, String body, {String? answeredBy}) => ChatMessage(
  id: '$role-$body',
  role: role,
  body: body,
  createdAt: DateTime(2026, 9, 1),
  answeredBy: answeredBy,
);

List<Override> overrides({
  List<ChatMessage> history = const [],
  int remaining = 3,
}) => [
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  coachHistoryProvider.overrideWith(
    (ref) async => (history.isEmpty ? null : 't1', history),
  ),
  coachRemainingProvider.overrideWith((ref) async => remaining),
];

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  setUpAll(loadTackFonts);

  testWidgets('an empty coach leads with the questions that cost nothing', (
    tester,
  ) async {
    // With three a day, a student who does not know which questions are free
    // will spend all three finding out.
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();

    expect(find.text('THESE ARE ALWAYS FREE'), findsOneWidget);
    for (final q in freeQuestions) {
      expect(find.text(q), findsOneWidget, reason: '$q should be offered');
    }
  });

  testWidgets('the allowance is shown before you type, not after', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(remaining: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('every reply says whether it cost anything', (tester) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(
        history: [
          msg('student', 'What should I do next?'),
          msg('coach', 'Your CV is worth 13 points.', answeredBy: 'data'),
          msg('student', 'How do I explain a gap year?'),
          msg('coach', 'Be honest and brief.', answeredBy: 'model'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From your own numbers · free'), findsOneWidget);
    expect(find.text('Used one of your three'), findsOneWidget);
  });

  testWidgets('a student line never claims to have cost anything', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(history: [msg('student', 'Hello')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('From your own numbers · free'), findsNothing);
    expect(find.text('Used one of your three'), findsNothing);
  });

  testWidgets('it lays out at the 360px floor without overflow', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 640),
      overrides: overrides(
        history: [
          msg('student', 'Is a to-do app good enough for my CV?'),
          msg(
            'coach',
            'A simple to-do app is usually too basic for a backend developer '
                'role. Since you currently have 0 out of 10 project points, '
                'building one can work if you focus purely on the backend.',
            answeredBy: 'model',
          ),
        ],
        remaining: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('running out is stated as a trade, never as a telling-off', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(remaining: 0),
    );
    await tester.pumpAndSettle();

    final text = bodyText(tester).toLowerCase();
    for (final blame in ['too many', 'exceeded', 'denied', 'blocked']) {
      expect(text.contains(blame), isFalse, reason: 'must not say "$blame"');
    }
    expect(find.text('0 of 3'), findsOneWidget);
  });
}
