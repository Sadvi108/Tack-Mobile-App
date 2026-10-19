import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/data/interview_models.dart';
import 'package:tack/features/interview/data/interview_repository.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';
import 'package:tack/features/profile/data/profile_repository.dart';

import '../../helpers.dart';

class _FakeRepository implements InterviewRepository {
  final graded = <(String, ReviewGrade)>[];

  @override
  Future<int> review(String questionId, ReviewGrade grade) async {
    graded.add((questionId, grade));
    return 3;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _due = [
  DueQuestion(
    questionId: 'q1',
    role: 'Data analyst',
    question: 'Tell me about a time you cleaned messy data.',
    answerText: 'I fixed a sales sheet with duplicate rows.',
    toImprove: ['Say what changed because of it'],
    modelAnswer: 'Situation, task, action, result.',
  ),
  DueQuestion(
    questionId: 'q2',
    role: 'Data analyst',
    question: 'Why this company?',
  ),
];

void main() {
  group('reading the practice list', () {
    test('a complete row becomes a due question', () {
      final due = DueQuestion.fromJson({
        'question_id': 'q1',
        'question': 'Why this role?',
        'role': 'QA engineer',
        'to_improve': ['Be specific', '', 3],
        'model_answer': 'Because…',
      })!;
      expect(due.role, 'QA engineer');
      expect(due.toImprove, ['Be specific']);
      expect(due.hasNotes, isTrue);
    });

    test('a row without a question is dropped, not drawn blank', () {
      expect(DueQuestion.fromJson({'question_id': 'q1'}), isNull);
      expect(DueQuestion.fromJson({'question': 'Why?'}), isNull);
      expect(
        DueQuestion.fromJson({'question_id': 'q1', 'question': '  '}),
        isNull,
      );
    });
  });

  group('practising again', () {
    setUpAll(loadTackFonts);

    late _FakeRepository repository;

    List<Override> overrides({List<DueQuestion> due = _due}) {
      repository = _FakeRepository();
      return [
        interviewRepositoryProvider.overrideWithValue(repository),
        dueQuestionsProvider.overrideWith((ref) async => due),
        interviewHistoryProvider.overrideWith((ref) async => const []),
        companyPacksProvider.overrideWith((ref) async => const []),
        profileProvider.overrideWith((ref) async => null),
      ];
    }

    testWidgets('due answers are offered, free, above the setup', (
      tester,
    ) async {
      await pumpAt(tester, const InterviewScreen(), overrides: overrides());
      await tester.pumpAndSettle();

      expect(find.text('Practise again'), findsOneWidget);
      expect(find.textContaining('2 answers are ready'), findsOneWidget);
      expect(find.textContaining('do not use AI actions'), findsOneWidget);
    });

    testWidgets('nothing due means no card', (tester) async {
      await pumpAt(
        tester,
        const InterviewScreen(),
        overrides: overrides(due: const []),
      );
      await tester.pumpAndSettle();
      expect(find.text('Practise again'), findsNothing);
    });

    testWidgets('notes stay hidden until asked for, then a grade moves on', (
      tester,
    ) async {
      await pumpAt(tester, const InterviewScreen(), overrides: overrides());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practise again'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tell me about a time you cleaned messy data.'),
        findsOneWidget,
      );
      expect(find.text('A strong answer'), findsNothing);
      expect(find.text('Good'), findsNothing);

      await tester.tap(find.text('Show my notes'));
      await tester.pumpAndSettle();
      expect(find.text('What you said last time'), findsOneWidget);
      expect(find.text('A strong answer'), findsOneWidget);
      for (final grade in ReviewGrade.values) {
        expect(find.text(grade.label), findsOneWidget);
      }
      expect(hasOverflow(tester), isFalse);

      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();
      expect(repository.graded, [('q1', ReviewGrade.good)]);
      expect(find.text('Why this company?'), findsOneWidget);
      expect(find.textContaining('2 of 2'), findsOneWidget);
    });

    testWidgets('a question with no notes says so rather than showing empty '
        'cards', (tester) async {
      await pumpAt(
        tester,
        const InterviewScreen(),
        overrides: overrides(due: [_due[1]]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practise again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show my notes'));
      await tester.pumpAndSettle();
      expect(find.text('No notes were saved for this one.'), findsOneWidget);
    });
  });
}
