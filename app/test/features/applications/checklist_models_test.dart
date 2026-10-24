import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/applications/data/checklist_models.dart';

void main() {
  group('the checklist', () {
    test('reads items in the order the server ranked them', () {
      final checklist = Checklist.fromJson({
        'items': [
          {
            'id': 'APP-DATE',
            'severity': 'required',
            'action': 'open_job',
            'title': 'Closes Sat 24 Oct. Send it, or let it go.',
          },
          {
            'id': 'APP-CV',
            'severity': 'recommended',
            'action': 'attach_cv',
            'title': 'Attach the CV you will send',
          },
        ],
        'next_step': {
          'id': 'APP-DATE',
          'severity': 'required',
          'action': 'open_job',
          'title': 'Closes Sat 24 Oct. Send it, or let it go.',
        },
      });

      expect(checklist.items.map((i) => i.id), ['APP-DATE', 'APP-CV']);
      expect(checklist.items.first.action, ChecklistAction.openJob);
      expect(checklist.items.first.isRequired, isTrue);
      expect(checklist.items.last.action, ChecklistAction.attachCv);
      expect(checklist.nextStep?.id, 'APP-DATE');
      expect(checklist.rest.map((i) => i.id), ['APP-CV']);
    });

    test('nothing to do is an empty checklist, not an error', () {
      final checklist = Checklist.fromJson({'items': [], 'next_step': null});
      expect(checklist.items, isEmpty);
      expect(checklist.nextStep, isNull);
      expect(checklist.isEmpty, isTrue);
    });

    test('an item it does not understand is left out', () {
      final checklist = Checklist.fromJson({
        'items': [
          {
            'id': 'APP-NEW',
            'severity': 'required',
            'action': 'teleport',
            'title': 'x',
          },
          {'id': 'APP-JD', 'severity': 'recommended', 'action': 'analyse'},
          {
            'id': 'APP-FOLLOW',
            'severity': 'recommended',
            'action': 'follow_up',
            'title': 'No reply in three weeks. Follow up, or move it on.',
          },
        ],
        'next_step': null,
      });
      expect(checklist.items.map((i) => i.id), ['APP-FOLLOW']);
    });

    test('a payload that is not a checklist is an empty one', () {
      expect(Checklist.fromJson(null).isEmpty, isTrue);
      expect(Checklist.fromJson('nope').isEmpty, isTrue);
    });
  });

  group('the prep brief', () {
    test('reads every section', () {
      final brief = PrepBrief.fromJson({
        'talking_points': [
          {
            'point': 'You can build their dashboards',
            'evidence': 'You list SQL',
          },
        ],
        'likely_questions': [
          {'question': 'Why this role?', 'why': 'Always asked.'},
        ],
        'questions_to_ask': ['What does a first month look like?'],
        'gaps': [
          {'skill': 'Power BI', 'how_to_prepare': 'Rebuild one report.'},
        ],
      })!;

      expect(
        brief.talkingPoints.single.point,
        'You can build their dashboards',
      );
      expect(brief.talkingPoints.single.evidence, 'You list SQL');
      expect(brief.likelyQuestions.single.why, 'Always asked.');
      expect(brief.questionsToAsk, ['What does a first month look like?']);
      expect(brief.gaps.single.howToPrepare, 'Rebuild one report.');
    });

    test('drops a malformed entry and keeps the rest', () {
      final brief = PrepBrief.fromJson({
        'talking_points': [
          {'point': 'No evidence'},
          {'point': 'Backed', 'evidence': 'Your flood map project'},
        ],
        'likely_questions': 'not a list',
        'questions_to_ask': ['Fine', 3],
        'gaps': [],
      })!;
      expect(brief.talkingPoints.map((p) => p.point), ['Backed']);
      expect(brief.likelyQuestions, isEmpty);
      expect(brief.questionsToAsk, ['Fine']);
    });

    test('no talking points is no brief', () {
      expect(PrepBrief.fromJson({'talking_points': []}), isNull);
      expect(PrepBrief.fromJson(null), isNull);
    });
  });
}
