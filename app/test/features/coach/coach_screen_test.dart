import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/core/supabase/client.dart';
import 'package:tack/design/tack.dart';
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

List<Override> shell() => [
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
];

List<Override> overrides({
  List<ChatMessage> history = const [],
  int remaining = 10,
}) => [
  ...shell(),
  coachHistoryProvider.overrideWith(
    (ref) async => (history.isEmpty ? null : 't1', history),
  ),
  aiAllowanceProvider.overrideWith(
    (ref) async => AiAllowance(used: 10 - remaining, limit: 10),
  ),
];

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

/// Serves whatever conversation the test has put in it, read fresh each time.
class _SavedThread extends Fake implements CoachRepository {
  _SavedThread(this.messages);

  List<ChatMessage> messages;
  int reads = 0;

  @override
  Future<(String?, List<ChatMessage>)> latestThread() async {
    reads++;
    return ('t1', List.of(messages));
  }
}

User _student() => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

void main() {
  setUpAll(loadTackFonts);

  testWidgets('an empty coach leads with the questions that cost nothing', (
    tester,
  ) async {
    // A student who does not know which questions are free will spend the
    // day's AI actions finding out.
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

  testWidgets('the free line names no daily number', (tester) async {
    // It said "three questions a day" long after the allowance changed.
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Tack answers these from your own numbers, so they never use an AI '
        'action.',
      ),
      findsOneWidget,
    );
    expect(bodyText(tester).toLowerCase(), isNot(contains('three questions')));
  });

  testWidgets('a reply is body text, never smaller than 16px', (tester) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 900),
      overrides: overrides(
        history: [
          msg('student', 'How do I explain a gap year?'),
          msg('coach', 'Be honest and brief.', answeredBy: 'model'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    for (final line in [
      'How do I explain a gap year?',
      'Be honest and brief.',
    ]) {
      final size = tester.widget<Text>(find.text(line)).style?.fontSize;
      expect(size, isNotNull, reason: line);
      expect(size, greaterThanOrEqualTo(16), reason: line);
    }
  });

  testWidgets('reopening the coach shows a reply that arrived since', (
    tester,
  ) async {
    // The history used to be cached for the life of the app, so a reply that
    // landed after the first visit stayed missing until a restart.
    final saved = _SavedThread([
      msg('student', 'How do I explain a gap year?'),
    ]);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/coach',
      routes: [
        GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
        GoRoute(path: '/home', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...shell(),
          currentUserProvider.overrideWithValue(_student()),
          coachRepositoryProvider.overrideWithValue(saved),
          aiAllowanceProvider.overrideWith(
            (ref) async => const AiAllowance(used: 0, limit: 10),
          ),
        ],
        child: MaterialApp.router(
          theme: buildTackTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Be honest and brief.'), findsNothing);

    router.go('/home');
    await tester.pumpAndSettle();
    saved.messages = [
      ...saved.messages,
      msg('coach', 'Be honest and brief.', answeredBy: 'model'),
    ];
    router.go('/coach');
    await tester.pumpAndSettle();

    expect(find.text('Be honest and brief.'), findsOneWidget);
    expect(saved.reads, 2);
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

    expect(find.text('2 of 10'), findsOneWidget);
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
    expect(find.text('Used one AI action'), findsOneWidget);
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
    expect(find.text('Used one AI action'), findsNothing);
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
    expect(find.text('0 of 10'), findsOneWidget);
  });
}
