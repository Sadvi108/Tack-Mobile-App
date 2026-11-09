import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:tack/core/analytics.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/core/supabase/client.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/coach/application/coach.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/features/coach/data/coach_repository.dart';
import 'package:tack/features/coach/presentation/coach_screen.dart';

import '../../helpers.dart';

ChatMessage msg(
  String role,
  String body, {
  String? answeredBy,
  List<CoachAction> actions = const [],
}) => ChatMessage(
  id: '$role-$body',
  role: role,
  body: body,
  createdAt: DateTime(2026, 9, 1),
  answeredBy: answeredBy,
  actions: actions,
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

/// Records events instead of sending them.
class FakeAnalytics extends Fake implements Analytics {
  final events = <(String, Map<String, Object?>?)>[];

  @override
  Future<void> track(String name, {Map<String, Object?>? properties}) async =>
      events.add((name, properties));

  @override
  void dispose() {}
}

/// The coach endpoint and the saved conversation, scripted by each test.
class FakeCoach extends Fake implements CoachRepository {
  FakeCoach({this.history = const [], this.answer});

  List<ChatMessage> history;
  Future<CoachReply> Function(String question)? answer;
  int reads = 0;
  final asked = <(String, String?)>[];

  @override
  Future<(String?, List<ChatMessage>)> latestThread() async {
    reads++;
    return (history.isEmpty ? null : 't1', List.of(history));
  }

  @override
  Future<CoachReply> ask(
    String question, {
    String? threadId,
    String? operationId,
    void Function(String jobId)? onQueued,
  }) {
    asked.add((question, operationId));
    return answer!(question);
  }
}

List<Override> overrides({
  List<ChatMessage> history = const [],
  int remaining = 10,
  YearMode mode = YearMode.explore,
  FakeCoach? coach,
  FakeAnalytics? analytics,
}) => [
  ...shell(),
  coachHistoryProvider.overrideWith(
    (ref) async => (history.isEmpty ? null : 't1', history),
  ),
  aiAllowanceProvider.overrideWith(
    (ref) async => AiAllowance(used: 10 - remaining, limit: 10),
  ),
  modeProvider.overrideWith((ref) => mode),
  analyticsProvider.overrideWithValue(analytics ?? FakeAnalytics()),
  if (coach != null) coachRepositoryProvider.overrideWithValue(coach),
];

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

User _student() => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

const _roadmap = CoachAction(route: 'roadmap', label: 'Open your roadmap');
const _score = CoachAction(route: 'score', label: 'See your score');
const _path = CoachAction(
  route: 'path',
  label: 'Read about Development programme associate',
  slug: 'development-programme-associate',
);

/// The coach inside a router that can reach the screens its chips open.
Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  List<Override> overrides, {
  Size size = const Size(360, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Widget page(String name) => Scaffold(body: Text('$name page'));
  final router = GoRouter(
    initialLocation: '/coach',
    routes: [
      GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
      GoRoute(path: '/home', builder: (_, _) => page('home')),
      GoRoute(path: '/roadmap', builder: (_, _) => page('roadmap')),
      GoRoute(path: '/score', builder: (_, _) => page('score')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(theme: buildTackTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await pumpAt(
    tester,
    const CoachScreen(),
    size: const Size(360, 900),
    overrides: overrides,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTackFonts);

  testWidgets('an empty coach leads with the questions that cost nothing', (
    tester,
  ) async {
    // A student who does not know which questions are free will spend the
    // day's AI actions finding out.
    await _pump(tester, overrides());

    expect(find.text('Ask me about your career'), findsOneWidget);
    expect(find.text('THESE ARE ALWAYS FREE'), findsOneWidget);
    for (final q in startersFor(YearMode.explore)) {
      expect(find.text(q), findsOneWidget, reason: '$q should be offered');
    }
  });

  testWidgets('a first-year is offered first-year starters', (tester) async {
    await _pump(tester, overrides(mode: YearMode.explore));
    expect(find.text('What skills am I missing?'), findsOneWidget);
    expect(find.text('What is coming up this week?'), findsNothing);
  });

  testWidgets('a final-year is offered final-year starters', (tester) async {
    await _pump(tester, overrides(mode: YearMode.launch));
    expect(find.text('What is coming up this week?'), findsOneWidget);
    expect(find.text('What skills am I missing?'), findsNothing);
  });

  testWidgets('the free line names no daily number', (tester) async {
    await _pump(tester, overrides());
    expect(
      find.text(
        'Tack answers these from your own numbers, so they never use an AI '
        'action.',
      ),
      findsOneWidget,
    );
    expect(bodyText(tester).toLowerCase(), isNot(contains('three questions')));
  });

  testWidgets('what is left shows before you type, and never the limit', (
    tester,
  ) async {
    await _pump(tester, overrides(remaining: 2));
    expect(find.text('2 AI actions left today'), findsOneWidget);
    final text = bodyText(tester);
    expect(text, isNot(contains('of 10')));
    expect(RegExp(r'\b\d+ of \d+\b').hasMatch(text), isFalse, reason: text);
  });

  testWidgets('running out is stated as a trade, never as a telling-off', (
    tester,
  ) async {
    await _pump(tester, overrides(remaining: 0));
    final text = bodyText(tester).toLowerCase();
    for (final blame in ['too many', 'exceeded', 'denied', 'blocked']) {
      expect(text.contains(blame), isFalse, reason: 'must not say "$blame"');
    }
    expect(find.text('No AI actions left today'), findsOneWidget);
    expect(text, isNot(contains('0 of 10')));
  });

  testWidgets('a reply is body text, never smaller than 16px', (tester) async {
    await _pump(
      tester,
      overrides(
        history: [
          msg('student', 'How do I explain a gap year?'),
          msg('coach', 'Be honest and brief.', answeredBy: 'model'),
        ],
      ),
    );
    for (final line in [
      'How do I explain a gap year?',
      'Be honest and brief.',
    ]) {
      final size = tester.widget<Text>(find.text(line)).style?.fontSize;
      expect(size, greaterThanOrEqualTo(16), reason: line);
    }
  });

  testWidgets('every reply says whether it cost anything', (tester) async {
    await _pump(
      tester,
      overrides(
        history: [
          msg('student', 'What should I do next?'),
          msg('coach', 'Your CV is worth 13 points.', answeredBy: 'data'),
          msg('student', 'How do I explain a gap year?'),
          msg('coach', 'Be honest and brief.', answeredBy: 'model'),
        ],
      ),
    );
    expect(find.text('From your own numbers · free'), findsOneWidget);
    expect(find.text('Used one AI action'), findsOneWidget);
  });

  testWidgets('a student line never claims to have cost anything', (
    tester,
  ) async {
    await _pump(tester, overrides(history: [msg('student', 'Hello')]));
    expect(find.text('From your own numbers · free'), findsNothing);
    expect(find.text('Used one AI action'), findsNothing);
  });

  testWidgets('chips from history open their screen and are counted', (
    tester,
  ) async {
    final analytics = FakeAnalytics();
    await _pumpRouted(
      tester,
      overrides(
        mode: YearMode.build,
        analytics: analytics,
        history: [
          msg('student', 'What should I do next?'),
          msg(
            'coach',
            'Finish your next roadmap task.',
            answeredBy: 'data',
            actions: [_roadmap, _score],
          ),
        ],
      ),
    );
    expect(find.text('Open your roadmap'), findsOneWidget);
    expect(find.text('See your score'), findsOneWidget);

    await tester.tap(find.text('Open your roadmap'));
    await tester.pumpAndSettle();

    expect(find.text('roadmap page'), findsOneWidget);
    expect(analytics.events.length, 1);
    expect(analytics.events.single.$1, 'coach_action_tapped');
    expect(analytics.events.single.$2, {'route': 'roadmap', 'mode': 'build'});
  });

  testWidgets('three chips fit at 360px without overflow', (tester) async {
    await pumpAt(
      tester,
      const CoachScreen(),
      size: const Size(360, 640),
      overrides: overrides(
        remaining: 0,
        history: [
          msg('student', 'Is a to-do app good enough for my CV?'),
          msg(
            'coach',
            'A simple to-do app is usually too basic for a backend developer '
                'role. Build one that saves to a real database instead.',
            answeredBy: 'model',
            actions: [_roadmap, _path, _score],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no actions left, the free questions stay tappable', (
    tester,
  ) async {
    final coach = FakeCoach(
      answer: (q) async => q == 'Explain my score'
          ? throw const Failure('Today is used up.', code: 'quota_exhausted')
          : const CoachReply(
              threadId: 't1',
              remaining: 0,
              body: 'You are on 41 out of 100.',
              answeredBy: 'data',
            ),
    );
    await _pump(tester, overrides(remaining: 0, coach: coach));

    await tester.tap(find.text('Explain my score'));
    await tester.pumpAndSettle();

    expect(find.text(coachQuotaMessage), findsOneWidget);
    expect(bodyText(tester), isNot(contains('of 10')));
    // The starters are offered again under the notice, and still work.
    await tester.tap(find.text('What skills am I missing?').last);
    await tester.pumpAndSettle();
    expect(coach.asked.map((a) => a.$1), [
      'Explain my score',
      'What skills am I missing?',
    ]);
    expect(find.text('You are on 41 out of 100.'), findsOneWidget);
  });

  testWidgets('a failed question is sent again as the same question', (
    tester,
  ) async {
    var calls = 0;
    final coach = FakeCoach(
      answer: (q) async {
        if (calls++ == 0) {
          throw const Failure('The coach is busy. Try again in a moment.');
        }
        return const CoachReply(
          threadId: 't1',
          remaining: 9,
          body: 'Here is what I would do.',
          answeredBy: 'model',
          actions: [_roadmap],
        );
      },
    );
    await _pump(tester, overrides(coach: coach));

    await tester.enterText(find.byType(EditableText), 'How do I network?');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The coach is busy. Try again in a moment.'), findsOne);

    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();

    expect(find.text('Here is what I would do.'), findsOneWidget);
    expect(find.text('How do I network?'), findsOneWidget);
    expect(coach.asked.length, 2);
    expect(coach.asked[0].$2, isNotNull);
    expect(coach.asked[1].$2, coach.asked[0].$2);
    expect(find.text('Open your roadmap'), findsOneWidget);
  });

  testWidgets('reopening the coach shows a reply that arrived since', (
    tester,
  ) async {
    // The history used to be cached for the life of the app, so a reply that
    // landed after the first visit stayed missing until a restart.
    final coach = FakeCoach(
      history: [msg('student', 'How do I explain a gap year?')],
    );
    final router = await _pumpRouted(tester, [
      ...shell(),
      currentUserProvider.overrideWithValue(_student()),
      coachRepositoryProvider.overrideWithValue(coach),
      aiAllowanceProvider.overrideWith(
        (ref) async => const AiAllowance(used: 0, limit: 10),
      ),
      modeProvider.overrideWith((ref) => YearMode.explore),
      analyticsProvider.overrideWithValue(FakeAnalytics()),
    ]);
    expect(find.text('How do I explain a gap year?'), findsOneWidget);
    expect(find.text('Be honest and brief.'), findsNothing);

    router.go('/home');
    await tester.pumpAndSettle();
    coach.history = [
      ...coach.history,
      msg('coach', 'Be honest and brief.', answeredBy: 'model'),
    ];
    router.go('/coach');
    await tester.pumpAndSettle();

    expect(find.text('Be honest and brief.'), findsOneWidget);
    expect(coach.reads, 2);
  });
}
