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
    };
    routes.forEach((type, expected) {
      expect(of(type).route, expected, reason: '$type should open $expected');
    });
  });

  test('an unknown type still goes somewhere sensible', () {
    expect(of('something_new').route, '/home');
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
