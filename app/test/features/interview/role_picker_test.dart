import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/application/interview.dart';
import 'package:tack/features/interview/data/interview_repository.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';

import '../../helpers.dart';

class _FakeRepository implements InterviewRepository {
  final started = <(String, InterviewType, Difficulty)>[];

  @override
  Future<InterviewSession> startPractice({
    required String roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timerEnabled,
    int count = 5,
  }) async {
    started.add((roleSlug, type, difficulty));
    return InterviewSession(
      id: 's1',
      role: 'QA engineer',
      roleSlug: roleSlug,
      type: type,
      difficulty: difficulty,
      timerEnabled: timerEnabled,
      questions: [
        for (var i = 0; i < 5; i++)
          InterviewQuestion(
            id: 'q$i',
            orderIndex: i,
            question: 'Question ${i + 1}?',
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAnalytics implements InterviewAnalytics {
  final events = <(String?, bool)>[];

  @override
  void started({
    String? roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool pack,
  }) => events.add((roleSlug, pack));
}

InterviewRole _role(
  String slug,
  String title, {
  List<String> aliases = const [],
}) => InterviewRole(
  slug: slug,
  title: title,
  summary: 'What a new $title does in the first year, in a sentence.',
  questionCount: 15,
  aliases: aliases,
);

/// Seven roles in one field: the largest field this round has.
final _software = InterviewField(
  slug: 'computer-science',
  name: 'Computer science and software',
  roles: [
    _role('software-engineer', 'Software engineer'),
    _role('backend-developer', 'Backend developer'),
    _role('frontend-developer', 'Frontend developer'),
    _role('full-stack-developer', 'Full stack developer'),
    _role('it-support-specialist', 'IT support specialist'),
    _role('mobile-app-developer', 'Mobile app developer'),
    _role('qa-engineer', 'QA engineer', aliases: ['sqa engineer', 'sqa']),
  ],
);

final _civil = InterviewField(
  slug: 'civil-engineering',
  name: 'Civil engineering',
  roles: [_role('civil-site-engineer', 'Civil site engineer')],
);

InterviewCatalog _catalog(
  RoleReason reason, {
  String slug = 'civil-site-engineer',
}) => InterviewCatalog(
  suggested: RoleSuggestion(
    slug: slug,
    title: slug == 'management-trainee'
        ? 'Management trainee'
        : 'Civil site engineer',
    fieldSlug: 'civil-engineering',
    fieldName: 'Civil engineering',
    reason: reason,
  ),
  fields: [_civil, _software],
);

void main() {
  setUpAll(loadTackFonts);

  late _FakeRepository repository;
  late _FakeAnalytics analytics;

  List<Override> overrides(InterviewCatalog catalog) {
    repository = _FakeRepository();
    analytics = _FakeAnalytics();
    return [
      interviewRepositoryProvider.overrideWithValue(repository),
      interviewAnalyticsProvider.overrideWithValue(analytics),
      interviewCatalogProvider.overrideWith((ref) async => catalog),
      dueQuestionsProvider.overrideWith((ref) async => const []),
      interviewHistoryProvider.overrideWith((ref) async => const []),
      companyPacksProvider.overrideWith((ref) async => const []),
    ];
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text('Practising for'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a role'), findsOneWidget);
  }

  testWidgets('the suggested role shows with where it came from', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_catalog(RoleReason.yourPath)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Civil site engineer'), findsOneWidget);
    expect(find.text('From the path you follow'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Practising for Civil site engineer. Change role'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Questions and self-checks are free'),
      findsOneWidget,
    );
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('a general suggestion says so', (tester) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(
        _catalog(RoleReason.general, slug: 'management-trainee'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Management trainee'), findsOneWidget);
    expect(
      find.text(
        'General graduate questions. Choose a role to make them specific.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no roles yet: choose a role, and start waits', (tester) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(InterviewCatalog.empty),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a role'), findsOneWidget);
    expect(find.text('Choose a role to start.'), findsOneWidget);
    await tester.tap(find.text('Start practising'));
    await tester.pumpAndSettle();
    expect(repository.started, isEmpty);
  });

  testWidgets('fields, then roles, then back to all fields', (tester) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_catalog(RoleReason.yourPath)),
    );
    await tester.pumpAndSettle();
    await openPicker(tester);

    expect(find.text('Computer science and software'), findsOneWidget);
    expect(find.text('7 roles'), findsOneWidget);
    expect(find.text('1 role'), findsOneWidget);

    await tester.tap(find.text('Computer science and software'));
    await tester.pumpAndSettle();
    expect(find.text('All fields'), findsOneWidget);
    expect(find.text('Backend developer'), findsOneWidget);
    // The largest field fits a 360px phone.
    expect(hasOverflow(tester), isFalse);

    await tester.tap(find.text('All fields'));
    await tester.pumpAndSettle();
    expect(find.text('7 roles'), findsOneWidget);
    expect(find.text('Backend developer'), findsNothing);
  });

  testWidgets('a search finds a role by a job ad name, or says nothing did', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_catalog(RoleReason.yourPath)),
    );
    await tester.pumpAndSettle();
    await openPicker(tester);

    await tester.enterText(find.byType(EditableText), 'sqa');
    await tester.pumpAndSettle();
    expect(find.text('QA engineer'), findsOneWidget);
    expect(find.text('Civil engineering'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'xylophone');
    await tester.pumpAndSettle();
    expect(
      find.text('No role matches that. Try a shorter word.'),
      findsOneWidget,
    );
  });

  testWidgets('start uses the chosen role, for free', (tester) async {
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: overrides(_catalog(RoleReason.yourPath)),
    );
    await tester.pumpAndSettle();
    await openPicker(tester);
    await tester.enterText(find.byType(EditableText), 'sqa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA engineer'));
    await tester.pumpAndSettle();

    // A role the student chose needs no reason line.
    expect(find.text('QA engineer'), findsOneWidget);
    expect(find.text('From the path you follow'), findsNothing);

    await tester.tap(find.text('Start practising'));
    await tester.pumpAndSettle();
    expect(repository.started, [
      ('qa-engineer', InterviewType.mixed, Difficulty.medium),
    ]);
    expect(analytics.events, [('qa-engineer', false)]);
    expect(find.text('Question 1?'), findsOneWidget);
  });

  testWidgets('a catalog that failed to load offers a retry in place', (
    tester,
  ) async {
    repository = _FakeRepository();
    await pumpAt(
      tester,
      const InterviewScreen(),
      overrides: [
        interviewRepositoryProvider.overrideWithValue(repository),
        interviewCatalogProvider.overrideWith(
          (ref) async => throw const Failure('offline'),
        ),
        dueQuestionsProvider.overrideWith((ref) async => const []),
        interviewHistoryProvider.overrideWith((ref) async => const []),
        companyPacksProvider.overrideWith((ref) async => const []),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Roles did not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Interview practice'), findsOneWidget);
  });
}
