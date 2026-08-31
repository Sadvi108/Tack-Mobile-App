import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/profile/data/profile.dart';

/// A complete payload, shaped exactly as `public.dashboard_feed()` returns it.
Map<String, dynamic> payload({
  Map<String, dynamic>? overrides,
}) => {
  'generated_at': '2026-08-26T09:00:00+00:00',
  'today': '2026-08-26',
  'profile': {
    'id': 'u1',
    'full_name': 'Rafiq Hossain',
    'mode': 'launch',
    'stage': 'bachelors',
    'target_role': 'Data analyst',
    'year_of_study': 4,
    'years_total': 4,
    'expected_graduation': '2026-12-31',
    'onboarding_completed_at': '2026-01-01T00:00:00+00:00',
  },
  'score': {
    'total': 42,
    'delta': 3,
    'mode': 'launch',
    'components': {
      'skills': {'earned': 6, 'max': 12, 'available': 6, 'ratio': 0.5},
      'cv_quality': {'earned': 0, 'max': 13, 'available': 13, 'ratio': 0},
    },
    'computed_at': '2026-08-25T18:00:00+00:00',
    'week_change': 5,
  },
  'cohort': {'average': 38, 'size': 24},
  'trend': [
    {'week': '2026-08-10', 'total': 34},
    {'week': '2026-08-17', 'total': 39},
    {'week': '2026-08-24', 'total': 42},
  ],
  'streak': {
    'current': 3,
    'longest': 9,
    'days': ['2026-08-24', '2026-08-25', '2026-08-26'],
  },
  'this_week': {
    'tasks_done': 2,
    'task_points': 8,
    'applications_added': 1,
    'interviews_practised': 0,
    'documents_added': 1,
    'score_gained': 5,
  },
  'last_week': {
    'tasks_done': 0,
    'task_points': 0,
    'applications_added': 0,
    'interviews_practised': 0,
    'documents_added': 0,
    'score_gained': 0,
  },
  'roadmap': {
    'done': 4,
    'total': 11,
    'overdue': 1,
    'active_milestone': 'Learn the tools',
    'next_task': {
      'id': 't1',
      'title': 'Finish the SQL course',
      'points': 5,
      'est_minutes': 90,
      'type': 'skill',
    },
  },
  'applications': {'applied': 6, 'interview': 1, 'nonsense': 3},
  'timeline': [
    {
      'kind': 'task',
      'id': 't1',
      'title': 'Finish the SQL course',
      'subtitle': 'Learn the tools',
      'on': '2026-08-24',
      'points': 5,
      'route': '/roadmap',
      'overdue': true,
    },
    {
      'kind': 'application',
      'id': 'a1',
      'title': 'Follow up',
      'subtitle': 'Data analyst · bKash',
      'on': '2026-08-28',
      'points': 0,
      'route': '/applications/a1',
      'overdue': false,
    },
  ],
  'skill_gap': [
    {'id': 's1', 'name': 'SQL', 'importance': 'core'},
    {'id': 's2', 'name': 'Statistics', 'importance': 'nice'},
  ],
  'skill_fit': {'have': 3, 'total': 8},
  'paths': {
    'chosen': 1,
    'primary_title': 'Data analyst',
    'primary_slug': 'data-analyst',
  },
  'documents': {'count': 2, 'has_cv': true},
  'unread_notifications': 4,
  ...?overrides,
};

void main() {
  group('reading a complete feed', () {
    final feed = DashboardFeed.fromJson(payload());

    test('the profile and mode come through', () {
      expect(feed.profile.fullName, 'Rafiq Hossain');
      expect(feed.mode, YearMode.launch);
      expect(feed.profile.yearOfStudy, 4);
    });

    test('score components are parsed into the model the app already uses', () {
      expect(feed.score.total, 42);
      expect(feed.weekChange, 5);
      expect(feed.areasCounted, 2);
      expect(feed.areasScored, 1);
    });

    test('application counts skip a status the app does not know', () {
      // The enum is the client's, and a status added server-side before the
      // app ships must not take the dashboard down with it.
      expect(feed.counts[TackStatus.applied], 6);
      expect(feed.counts[TackStatus.interview], 1);
      expect(feed.counts.total, 7);
    });

    test('the timeline splits into late and upcoming', () {
      expect(feed.overdue.map((e) => e.title), ['Finish the SQL course']);
      expect(feed.upcoming.map((e) => e.title), ['Follow up']);
    });

    test('skill fit is a fraction of what the path asks for', () {
      expect(feed.skillsHeld, 3);
      expect(feed.skillsAsked, 8);
      expect(feed.skillFit, closeTo(0.375, 0.001));
    });

    test('the next roadmap task is carried, not the whole roadmap', () {
      expect(feed.roadmap.nextTaskTitle, 'Finish the SQL course');
      expect(feed.roadmap.nextTaskPoints, 5);
      expect(feed.roadmap.percent, 36);
    });
  });

  group('reading a feed that is missing things', () {
    test('an empty object parses into an empty dashboard, not an exception', () {
      // This is a real state: a student whose profile row exists but who has
      // done nothing yet. It must render, not throw.
      final feed = DashboardFeed.fromJson({});

      expect(feed.score.total, 0);
      expect(feed.streak.current, 0);
      expect(feed.timeline, isEmpty);
      expect(feed.counts.total, 0);
      expect(feed.cohortAverage, isNull);
      expect(feed.skillFit, 0);
    });

    test('nulls where objects are expected are survivable', () {
      final feed = DashboardFeed.fromJson(
        payload(
          overrides: {
            'cohort': null,
            'streak': null,
            'roadmap': null,
            'skill_gap': null,
            'timeline': null,
          },
        ),
      );

      expect(feed.cohortAverage, isNull);
      expect(feed.streak.current, 0);
      expect(feed.roadmap.total, 0);
      expect(feed.skillGap, isEmpty);
      expect(feed.timeline, isEmpty);
      // And the parts that were present are still there.
      expect(feed.score.total, 42);
    });

    test('a roadmap with no next task is not a broken roadmap', () {
      final feed = DashboardFeed.fromJson(
        payload(
          overrides: {
            'roadmap': {'done': 11, 'total': 11, 'overdue': 0},
          },
        ),
      );

      expect(feed.roadmap.nextTaskId, isNull);
      expect(feed.roadmap.percent, 100);
      expect(feed.roadmap.exists, isTrue);
    });
  });

  group('relative dates', () {
    final today = DateTime(2026, 8, 26);
    TimelineEntry on(int offset) => TimelineEntry(
      kind: TimelineKind.task,
      id: 'x',
      title: 'x',
      on: today.add(Duration(days: offset)),
      route: '/roadmap',
      isOverdue: offset < 0,
    );

    test('a student is told how long, never a bare date', () {
      // "12 Sep" makes a student do the subtraction; the day they get it
      // wrong is the day they miss something.
      expect(on(0).relativeTo(today), 'Today');
      expect(on(1).relativeTo(today), 'Tomorrow');
      expect(on(3).relativeTo(today), 'In 3 days');
      expect(on(9).relativeTo(today), 'Next week');
      expect(on(-1).relativeTo(today), 'Yesterday');
      expect(on(-4).relativeTo(today), '4 days late');
    });

    test('a time of day never changes which day something falls on', () {
      // The feed sends dates; a local timestamp late at night must not round
      // an item into tomorrow.
      final late = TimelineEntry(
        kind: TimelineKind.task,
        id: 'x',
        title: 'x',
        on: DateTime(2026, 8, 26, 23, 55),
        route: '/roadmap',
        isOverdue: false,
      );
      expect(late.relativeTo(DateTime(2026, 8, 26, 0, 5)), 'Today');
    });
  });

  group('the streak', () {
    test('knows which days were active', () {
      final streak = Streak.fromJson({
        'current': 2,
        'longest': 5,
        'days': ['2026-08-25', '2026-08-26'],
      });

      expect(streak.wasActiveOn(DateTime(2026, 8, 26)), isTrue);
      expect(streak.wasActiveOn(DateTime(2026, 8, 24)), isFalse);
    });

    test('a personal best is a run at least as long as the record', () {
      expect(
        const Streak(current: 5, longest: 5, days: []).isPersonalBest,
        isTrue,
      );
      expect(
        const Streak(current: 4, longest: 5, days: []).isPersonalBest,
        isFalse,
      );
      // Zero is never a personal best, whatever the record says.
      expect(
        const Streak(current: 0, longest: 0, days: []).isPersonalBest,
        isFalse,
      );
    });
  });
}
