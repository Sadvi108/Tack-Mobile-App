import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/data/interview_models.dart';

Map<String, dynamic> _question(
  int index, {
  bool skipped = false,
  String? answer,
  Map<String, dynamic>? feedback,
  Object? selfCheck,
  Object? keyPoints,
}) => {
  'id': 'q$index',
  'order_index': index,
  'question': 'Question $index?',
  'category': 'Basics',
  'answer_text': answer,
  'skipped': skipped,
  'interview_feedback': feedback == null ? const [] : [feedback],
  'self_check': ?selfCheck,
  'key_points': ?keyPoints,
};

Map<String, dynamic> _session(List<Map<String, dynamic>> questions) => {
  'id': 's1',
  'role': 'Data analyst',
  'session_type': 'mixed',
  'difficulty': 'medium',
  'timer_enabled': false,
  'interview_questions': questions,
};

void main() {
  group('key points', () {
    test('only trimmed, non-blank strings, at most four', () {
      expect(parseKeyPoints(null), isEmpty);
      expect(parseKeyPoints('Say what changed'), isEmpty);
      expect(parseKeyPoints({'a': 'b'}), isEmpty);
      expect(parseKeyPoints([' One ', 2, '', '  ', null, 'Two']), [
        'One',
        'Two',
      ]);
      expect(parseKeyPoints(['A1', 'B2', 'C3', 'D4', 'E5']), [
        'A1',
        'B2',
        'C3',
        'D4',
      ]);
    });

    test('a question carries its key points and pool id', () {
      final q = InterviewQuestion.fromRow({
        ..._question(0, keyPoints: ['Names one example', 7]),
        'pool_question_id': 'p1',
      });
      expect(q.keyPoints, ['Names one example']);
      expect(q.poolQuestionId, 'p1');
      expect(
        InterviewQuestion.fromRow({
          ..._question(1),
          'pool_question_id': 3,
        }).poolQuestionId,
        isNull,
      );
    });
  });

  group('self-check', () {
    test('a good check parses and round-trips', () {
      final check = SelfCheck.fromJson({
        'covered': [2, 0],
        'total': 4,
      })!;
      expect(check.covered, [0, 2]);
      expect(check.total, 4);
      expect(check.toJson(), {
        'covered': [0, 2],
        'total': 4,
      });
    });

    test('bad input is no check', () {
      expect(SelfCheck.fromJson(null), isNull);
      expect(SelfCheck.fromJson('covered'), isNull);
      expect(
        SelfCheck.fromJson({
          'covered': [0],
        }),
        isNull,
      );
      expect(SelfCheck.fromJson({'covered': 0, 'total': 2}), isNull);
      expect(SelfCheck.fromJson({'covered': [], 'total': 0}), isNull);
      expect(SelfCheck.fromJson({'covered': [], 'total': 5}), isNull);
      expect(SelfCheck.fromJson({'covered': [], 'total': '2'}), isNull);
    });

    test('out-of-range and repeated indexes are dropped', () {
      final check = SelfCheck.fromJson({
        'covered': [1, 1, -1, 3, 'x', 0],
        'total': 3,
      })!;
      expect(check.covered, [0, 1]);
    });
  });

  group('a session', () {
    test('an old row without the new keys parses as it did before', () {
      final session = InterviewSession.fromRow(
        _session([
          _question(1, answer: 'An answer'),
          _question(0, skipped: true),
        ]),
      );
      expect(session.roleSlug, isNull);
      expect(session.questions.map((q) => q.id), ['q0', 'q1']);
      expect(session.questions.first.skipped, isTrue);
      final q = session.questions.last;
      expect(q.keyPoints, isEmpty);
      expect(q.poolQuestionId, isNull);
      expect(q.selfCheck, isNull);
      expect(q.answerText, 'An answer');
      expect(session.answeredCount, 2);
    });

    test('nothing scored by AI stores no score, so readiness is untouched', () {
      // A free session used to store 0, which pulled the readiness score
      // down for practising.
      final skipped = InterviewSession.fromRow(
        _session([_question(0, skipped: true), _question(1, skipped: true)]),
      );
      expect(skipped.overallForStorage, isNull);
      expect(skipped.anyAiScored, isFalse);

      final selfChecked = InterviewSession.fromRow({
        ..._session([
          _question(
            0,
            answer: 'Mine',
            selfCheck: {
              'covered': [0, 1],
              'total': 3,
            },
          ),
          _question(
            1,
            answer: 'Mine too',
            selfCheck: {
              'covered': [2],
              'total': 4,
            },
          ),
        ]),
        'role_slug': 'data-analyst',
      });
      expect(selfChecked.roleSlug, 'data-analyst');
      expect(selfChecked.overallForStorage, isNull);
      expect(selfChecked.attempted, 2);
      expect(selfChecked.keyPointsCovered, 3);
      expect(selfChecked.keyPointsTotal, 7);
    });

    test('the AI average when something was scored', () {
      final session = InterviewSession.fromRow(
        _session([
          _question(0, answer: 'A', feedback: {'score': 6}),
          _question(1, answer: 'B', feedback: {'score': 8}),
          _question(
            2,
            answer: 'C',
            selfCheck: {
              'covered': [0],
              'total': 2,
            },
          ),
          _question(3, skipped: true),
        ]),
      );
      expect(session.anyAiScored, isTrue);
      expect(session.overallForStorage, 7);
      expect(session.attempted, 3);
    });
  });

  group('due questions', () {
    test('key points and category come through', () {
      final due = DueQuestion.fromJson({
        'question_id': 'q1',
        'question': 'Why this role?',
        'key_points': ['Names the role', '', 4],
        'category': 'Motivation',
      })!;
      expect(due.keyPoints, ['Names the role']);
      expect(due.category, 'Motivation');
    });

    test('key points alone are notes', () {
      final due = DueQuestion.fromJson({
        'question_id': 'q1',
        'question': 'Why this role?',
        'key_points': ['Names the role'],
      })!;
      expect(due.hasNotes, isTrue);
      final bare = DueQuestion.fromJson({
        'question_id': 'q2',
        'question': 'Why this role?',
        'category': 3,
      })!;
      expect(bare.hasNotes, isFalse);
      expect(bare.keyPoints, isEmpty);
      expect(bare.category, isNull);
    });
  });
}
