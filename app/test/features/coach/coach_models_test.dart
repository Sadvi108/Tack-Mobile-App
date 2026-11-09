import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/coach/data/coach_models.dart';

void main() {
  group('reading actions', () {
    test('a well-formed action is read as it was sent', () {
      final a = CoachAction.fromJson({
        'route': 'path',
        'label': 'Read about Data analyst',
        'slug': 'data-analyst',
      });
      expect(a, isNotNull);
      expect(a!.route, 'path');
      expect(a.label, 'Read about Data analyst');
      expect(a.slug, 'data-analyst');
    });

    test('anything malformed, unknown or badly slugged is dropped', () {
      final list = CoachAction.listFrom([
        {'route': 'roadmap', 'label': 'Open your roadmap'},
        {'route': 'teleport', 'label': 'Somewhere new'},
        {'route': 'path', 'label': 'Read about it', 'slug': 'Not A Slug'},
        {'route': 'score'},
        {'route': 'score', 'label': 'S'},
        {'route': 7, 'label': 'Seven'},
        'roadmap',
        null,
        {'route': 'score', 'label': 'See your score'},
      ]);
      expect(list.map((a) => a.route), ['roadmap', 'score']);
    });

    test('at most three, and nothing at all reads as none', () {
      final four = [
        for (final route in ['roadmap', 'score', 'paths', 'profile'])
          {'route': route, 'label': 'Open it'},
      ];
      expect(CoachAction.listFrom(four).length, 3);
      expect(CoachAction.listFrom(null), isEmpty);
      expect(CoachAction.listFrom({'route': 'roadmap'}), isEmpty);
    });
  });

  group('messages and replies', () {
    test('a saved reply carries its actions and intent', () {
      final m = ChatMessage.fromRow({
        'id': 'm1',
        'role': 'coach',
        'body': 'Open your roadmap.',
        'created_at': '2026-11-06T10:00:00Z',
        'answered_by': 'data',
        'intent': 'next',
        'actions': [
          {'route': 'roadmap', 'label': 'Open your roadmap'},
        ],
      });
      expect(m.actions.single.route, 'roadmap');
      expect(m.intent, 'next');
    });

    test('a reply saved before 0097 has no actions and no intent', () {
      final m = ChatMessage.fromRow({
        'id': 'm1',
        'role': 'coach',
        'body': 'Old.',
        'created_at': '2026-09-01T10:00:00Z',
        'answered_by': 'model',
      });
      expect(m.actions, isEmpty);
      expect(m.intent, isNull);
    });

    test('a fresh reply carries them too, and tolerates their absence', () {
      final r = CoachReply.fromJson({
        'threadId': 't1',
        'remaining': 4,
        'reply': 'Hi.',
        'answeredBy': 'data',
        'intent': 'score',
        'actions': [
          {'route': 'score', 'label': 'See your score'},
        ],
      });
      expect(r.actions.single.label, 'See your score');
      expect(r.intent, 'score');

      final old = CoachReply.fromJson({'threadId': 't1', 'reply': 'Hi.'});
      expect(old.actions, isEmpty);
      expect(old.intent, isNull);
    });
  });
}
