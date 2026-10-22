import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';

TackNotification of(String type) => TackNotification(
  id: 'n1',
  type: type,
  title: 'x',
  createdAt: DateTime(2026, 9, 4),
);

void main() {
  // The digest written by enqueue_daily_digest() is about roadmap steps, so a
  // tap has to land on the roadmap. It used to fall through to the dashboard,
  // which is where you go when Tack does not know — and wasting the tap is the
  // whole point of having sent the reminder.
  test('every type the server writes has somewhere to go', () {
    const routes = {
      'analysis_ready': '/analyser',
      'cv_parsed': '/vault',
      'deadline': '/applications',
      'score_changed': '/score',
      'step_due': '/roadmap',
      // The brief is opened as a sheet from the updates list.
      'weekly_brief': '/notifications',
    };
    routes.forEach((type, expected) {
      expect(of(type).route, expected, reason: '$type should open $expected');
    });
  });

  test('an unknown type still goes somewhere sensible', () {
    expect(of('something_new').route, '/home');
  });

  group('the weekly brief', () {
    TackNotification brief(Object? items) => TackNotification.fromRow({
      'id': 'n3',
      'type': 'weekly_brief',
      'title': 'Your week: 3 things',
      'created_at': '2026-10-26T03:00:00Z',
      'payload': {'items': items},
    });

    test('reads the items the server ranked, in order', () {
      final items = brief([
        {
          'title': 'Meghna Foods closes Wed 28 Oct',
          'why': 'Send your application before then, or let it go.',
          'route': '/applications/7b0c1a52-9a52-4c7e-9a43-3f1f5d3b2a10',
        },
        {
          'title': 'One roadmap step is late',
          'why': 'Move a date or tick one off.',
          'route': '/roadmap',
        },
      ]).briefItems;

      expect(items.map((i) => i.title), [
        'Meghna Foods closes Wed 28 Oct',
        'One roadmap step is late',
      ]);
      expect(
        items.first.route,
        '/applications/7b0c1a52-9a52-4c7e-9a43-3f1f5d3b2a10',
      );
      expect(items.last.why, 'Move a date or tick one off.');
    });

    test('drops an item that is missing a field', () {
      final items = brief([
        {'title': 'No reason given', 'route': '/roadmap'},
        {'title': 'Fine', 'why': 'Because.', 'route': '/radar'},
      ]).briefItems;
      expect(items.map((i) => i.title), ['Fine']);
    });

    test('never follows a route outside the places a brief can point', () {
      final items = brief([
        {'title': 'Odd', 'why': 'x', 'route': 'https://example.com'},
        {'title': 'Settings', 'why': 'x', 'route': '/settings'},
        {'title': 'Lookalike', 'why': 'x', 'route': '/roadmapx'},
        {'title': 'Climb', 'why': 'x', 'route': '/radar/../settings'},
        {'title': 'No id', 'why': 'x', 'route': '/applications/'},
        {
          'title': 'Not an id',
          'why': 'x',
          'route': '/applications/../settings',
        },
        {'title': 'Practice', 'why': 'x', 'route': '/interview'},
      ]).briefItems;
      expect(items.map((i) => i.route), ['/interview']);
    });

    test('anything that is not a list of items is no items', () {
      expect(brief('not a list').briefItems, isEmpty);
      expect(brief(null).briefItems, isEmpty);
      expect(of('step_due').briefItems, isEmpty);
    });
  });

  test('unread is the absence of a read time, not a flag', () {
    expect(of('general').isUnread, isTrue);
    expect(
      TackNotification(
        id: 'n2',
        type: 'general',
        title: 'x',
        createdAt: DateTime(2026, 9, 4),
        readAt: DateTime(2026, 9, 4),
      ).isUnread,
      isFalse,
    );
  });
}
