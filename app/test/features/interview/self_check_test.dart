import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/application/interview.dart';
import 'package:tack/features/interview/data/interview_repository.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';
import 'package:tack/features/interview/presentation/review_view.dart';
import 'package:tack/features/interview/presentation/summary_view.dart';

import '../../helpers.dart';

const _points = [
  'Says what the problem was',
  'Names one thing they did',
  'Gives the result in numbers',
  'Says what they learned',
];

const _answer = 'I cleaned a sales sheet that had duplicate rows in it.';

InterviewQuestion _q(
  int i, {
  List<String> keyPoints = _points,
  String? answer,
  SelfCheck? check,
}) => InterviewQuestion(
  id: 'q$i',
  orderIndex: i,
  question: 'Question ${i + 1}?',
  category: 'Data quality',
  keyPoints: keyPoints,
  answerText: answer,
  selfCheck: check,
);

InterviewSession _session(List<InterviewQuestion> questions, {String? done}) =>
    InterviewSession(
      id: 's1',
      role: 'Data analyst',
      roleSlug: 'data-analyst',
      type: InterviewType.technical,
      difficulty: Difficulty.medium,
      timerEnabled: false,
      questions: questions,
      completedAt: done == null ? null : DateTime(2026, 11, 8),
    );

class _FakeRepository implements InterviewRepository {
  _FakeRepository(this.session);

  InterviewSession session;
  final saved = <(String, String, List<int>, int)>[];
  final submitted = <String>[];
  Object? saveError;

  @override
  Future<InterviewSession> startPractice({
    required String roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timerEnabled,
    int count = 5,
  }) async => session;

  @override
  Future<InterviewSession> startFromPack({
    required CompanyPack pack,
    required bool timerEnabled,
  }) async => session;

  @override
  Future<void> saveOwnAnswer({
    required String questionId,
    required String answer,
    required List<int> covered,
    required int total,
  }) async {
    if (saveError case final error?) throw error;
    saved.add((questionId, answer, covered, total));
    session = _session([
      for (final q in session.questions)
        q.id == questionId
            ? _q(
                q.orderIndex,
                keyPoints: q.keyPoints,
                answer: answer,
                check: SelfCheck(covered: covered, total: total),
              )
            : q,
    ]);
  }

  @override
  Future<AnswerFeedback> submitAnswer({
    required String questionId,
    required String answer,
  }) async {
    submitted.add(questionId);
    return const AnswerFeedback(
      score: 7,
      wentWell: ['A clear example'],
      toImprove: ['Say what changed'],
    );
  }

  @override
  Future<InterviewSession?> byId(String id) async => session;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAnalytics implements InterviewAnalytics {
  @override
  void started({
    String? roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool pack,
  }) {}
}

const _catalog = InterviewCatalog(
  suggested: RoleSuggestion(
    slug: 'data-analyst',
    title: 'Data analyst',
    fieldSlug: 'statistics',
    fieldName: 'Statistics and data science',
    reason: RoleReason.yourPath,
  ),
  fields: [
    InterviewField(
      slug: 'statistics',
      name: 'Statistics and data science',
      roles: [InterviewRole(slug: 'data-analyst', title: 'Data analyst')],
    ),
  ],
);

const _pack = CompanyPack(
  slug: 'pathao',
  name: 'Pathao',
  about: 'Ride-hailing, delivery and courier services.',
  questions: ['Question 1?', 'Question 2?'],
);

void main() {
  setUpAll(loadTackFonts);

  late _FakeRepository repository;

  List<Override> overrides(
    InterviewSession session, {
    List<CompanyPack> packs = const [],
  }) {
    repository = _FakeRepository(session);
    return [
      interviewRepositoryProvider.overrideWithValue(repository),
      interviewAnalyticsProvider.overrideWithValue(_FakeAnalytics()),
      interviewCatalogProvider.overrideWith((ref) async => _catalog),
      dueQuestionsProvider.overrideWith((ref) async => const []),
      interviewHistoryProvider.overrideWith((ref) async => const []),
      companyPacksProvider.overrideWith((ref) async => packs),
    ];
  }

  Future<void> startAndAnswer(WidgetTester tester, String answer) async {
    await tester.tap(find.text('Start practising'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), answer);
    await tester.pumpAndSettle();
  }

  testWidgets('key points stay hidden until the student checks', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_session([_q(0), _q(1)])),
    );
    await tester.pumpAndSettle();
    await startAndAnswer(tester, _answer);

    expect(find.text('Question 1?'), findsOneWidget);
    expect(find.text(_points.first), findsNothing);
    expect(
      find.text('Checking is free. AI feedback uses one AI action.'),
      findsOneWidget,
    );
    expect(find.text('Submit answer'), findsNothing);

    await tester.tap(find.text('Check against key points'));
    await tester.pumpAndSettle();
    expect(find.text('A strong answer covers'), findsOneWidget);
    for (final point in _points) {
      expect(find.text(point), findsOneWidget);
    }
    expect(find.text('You covered 0 of 4.'), findsOneWidget);
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('ticking two of four saves them, free, and moves on', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_session([_q(0), _q(1)])),
    );
    await tester.pumpAndSettle();
    await startAndAnswer(tester, _answer);
    await tester.tap(find.text('Check against key points'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_points[0]));
    await tester.tap(find.text(_points[2]));
    await tester.pumpAndSettle();
    expect(find.text('You covered 2 of 4.'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_points[0])),
      matchesSemantics(
        label: _points[0],
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.text('Next question'));
    await tester.pumpAndSettle();
    expect(repository.saved, hasLength(1));
    final (id, answer, covered, total) = repository.saved.single;
    expect(id, 'q0');
    expect(answer, _answer);
    expect(covered, [0, 2]);
    expect(total, 4);
    expect(repository.submitted, isEmpty);
    expect(find.text('Question 2?'), findsOneWidget);
  });

  testWidgets('a failed save keeps the answer and the ticks on screen', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_session([_q(0), _q(1)])),
    );
    repository.saveError = const Failure(
      'You are offline. Connect and try again.',
    );
    await tester.pumpAndSettle();
    await startAndAnswer(tester, _answer);
    await tester.tap(find.text('Check against key points'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_points[1]));
    await tester.tap(find.text('Next question'));
    await tester.pump();

    expect(
      find.text('You are offline. Connect and try again.'),
      findsOneWidget,
    );
    expect(find.text('You covered 1 of 4.'), findsOneWidget);
    await tester.tap(find.text('What you said'));
    await tester.pump();
    expect(find.text(_answer), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('AI feedback shows what a strong answer covers', (tester) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_session([_q(0), _q(1)])),
    );
    await tester.pumpAndSettle();
    await startAndAnswer(tester, _answer);
    await tester.tap(find.text('Get AI feedback'));
    await tester.pumpAndSettle();

    expect(repository.submitted, ['q0']);
    expect(find.text('What went well'), findsOneWidget);
    expect(find.text('A strong answer covers'), findsOneWidget);
    expect(find.text(_points.last), findsOneWidget);
  });

  testWidgets('without key points the single submit works as before', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_session([_q(0, keyPoints: const []), _q(1)])),
    );
    await tester.pumpAndSettle();
    await startAndAnswer(tester, _answer);

    expect(find.text('Check against key points'), findsNothing);
    await tester.tap(find.text('Submit answer'));
    await tester.pumpAndSettle();
    expect(repository.submitted, ['q0']);
    expect(find.text('What went well'), findsOneWidget);
    expect(find.text('A strong answer covers'), findsNothing);
  });

  testWidgets('practise again shows what a strong answer covers', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ReviewView(
        questions: const [
          DueQuestion(
            questionId: 'q1',
            role: 'Data analyst',
            question: 'Tell me about a time you cleaned messy data.',
            answerText: _answer,
            keyPoints: _points,
          ),
        ],
        onDone: () {},
      ),
      overrides: overrides(_session([_q(0)])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show my notes'));
    await tester.pumpAndSettle();
    expect(find.text('What a strong answer covers'), findsOneWidget);
    expect(find.textContaining(_points.first), findsOneWidget);
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('a self-checked summary counts key points, never out of ten', (
    tester,
  ) async {
    await pumpAt(
      tester,
      SummaryView(
        session: _session([
          _q(
            0,
            answer: 'A',
            check: const SelfCheck(covered: [0, 2], total: 4),
          ),
          _q(
            1,
            answer: 'B',
            check: const SelfCheck(covered: [1], total: 3),
          ),
        ], done: 'yes'),
        onAgain: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('key points covered'), findsOneWidget);
    expect(find.text('of 10'), findsNothing);
    expect(find.textContaining('/10'), findsNothing);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('a company pack says who wrote it, listed and started', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(
        _session([_q(0, keyPoints: const []), _q(1, keyPoints: const [])]),
        packs: const [_pack],
      ),
    );
    await tester.pumpAndSettle();
    const line =
        'Written by Tack for practice. Pathao did not write or check these.';
    await tester.scrollUntilVisible(find.text(line), 200);
    expect(find.text(line), findsOneWidget);

    await tester.tap(find.text('Pathao'));
    await tester.pumpAndSettle();
    expect(find.text('Question 1?'), findsOneWidget);
    expect(find.text(line), findsOneWidget);
    expect(hasOverflow(tester), isFalse);
  });
}
