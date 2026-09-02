import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/dashboard/application/insights.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/score/data/readiness.dart';

final today = DateTime(2026, 8, 26);

DashboardFeed feed({
  YearMode mode = YearMode.launch,
  bool hasCv = true,
  int chosenPaths = 1,
  String? primaryPathTitle = 'Data analyst',
  Streak streak = Streak.empty,
  WeekSummary thisWeek = WeekSummary.empty,
  WeekSummary lastWeek = WeekSummary.empty,
  List<TimelineEntry> timeline = const [],
  List<SkillGap> skillGap = const [],
  RoadmapSummary roadmap = RoadmapSummary.empty,
  ApplicationCounts counts = ApplicationCounts.empty,
}) => DashboardFeed(
  today: today,
  profile: Profile(id: 'u1', fullName: 'Rafiq Hossain', mode: mode),
  score: ReadinessScore(
    total: 30,
    mode: mode,
    delta: 0,
    computedAt: today,
    components: const [],
  ),
  weekChange: 0,
  streak: streak,
  thisWeek: thisWeek,
  lastWeek: lastWeek,
  trend: const [],
  roadmap: roadmap,
  counts: counts,
  timeline: timeline,
  skillGap: skillGap,
  skillsHeld: 3,
  skillsAsked: 8,
  cohortAverage: null,
  cohortSize: null,
  chosenPaths: chosenPaths,
  availablePaths: 10,
  primaryPathTitle: primaryPathTitle,
  primaryPathSlug: 'data-analyst',
  following: const [],
  documentCount: hasCv ? 1 : 0,
  hasCv: hasCv,
  unreadNotifications: 0,
);

/// A week's activity, with `moves` totalled the way the database totals it.
///
/// `moves` is authoritative and no longer summed from the named fields — that
/// is the whole point of the fix — so a test that wants a busy week has to say
/// how busy, not just list two of the things in it.
WeekSummary week({
  int tasksDone = 0,
  int taskPoints = 0,
  int applicationsAdded = 0,
  int interviewsPractised = 0,
  int documentsAdded = 0,
  int skillsAdded = 0,
  int projectsAdded = 0,
  int scoreGained = 0,
  int? moves,
  int activeDays = 0,
}) {
  final counted =
      tasksDone +
      applicationsAdded +
      interviewsPractised +
      documentsAdded +
      skillsAdded +
      projectsAdded;
  return WeekSummary(
    moves: moves ?? counted,
    activeDays: activeDays,
    tasksDone: tasksDone,
    taskPoints: taskPoints,
    applicationsAdded: applicationsAdded,
    interviewsPractised: interviewsPractised,
    documentsAdded: documentsAdded,
    skillsAdded: skillsAdded,
    projectsAdded: projectsAdded,
    scoreGained: scoreGained,
  );
}

TimelineEntry entry({
  required String title,
  required int inDays,
  TimelineKind kind = TimelineKind.task,
}) => TimelineEntry(
  kind: kind,
  id: title,
  title: title,
  on: today.add(Duration(days: inDays)),
  route: '/roadmap',
  isOverdue: inDays < 0,
);

List<String> idsOf(List<Insight> insights) =>
    insights.map((i) => i.id).toList();

void main() {
  group('what gets suggested', () {
    test('nothing is invented for an account with nothing in it', () {
      // A set-up student with an empty week gets suggestions drawn from real
      // gaps, and nothing else. No filler, no encouragement with no basis.
      final insights = buildInsights(
        feed(hasCv: true, chosenPaths: 1, primaryPathTitle: null),
      );
      expect(insights, isEmpty);
    });

    test('a missing CV and a missing path are both named', () {
      final insights = buildInsights(
        feed(hasCv: false, chosenPaths: 0, primaryPathTitle: null),
      );
      expect(idsOf(insights), containsAll(['no-cv', 'no-path']));
    });

    test('late things come before everything else', () {
      final insights = buildInsights(
        feed(
          hasCv: false,
          streak: const Streak(current: 6, longest: 6, days: []),
          timeline: [entry(title: 'Finish the SQL course', inDays: -3)],
        ),
      );
      expect(insights.first.id, 'overdue');
      expect(insights.first.tone, InsightTone.urgent);
    });

    test('one late thing is named; several are counted', () {
      final one = buildInsights(
        feed(timeline: [entry(title: 'Finish the SQL course', inDays: -1)]),
      );
      expect(one.first.title, 'Finish the SQL course');

      final many = buildInsights(
        feed(
          timeline: [
            entry(title: 'Finish the SQL course', inDays: -1),
            entry(title: 'Ship the project', inDays: -4),
          ],
        ),
      );
      expect(many.first.title, '2 things slipped past');
    });

    test('the deck is capped so it stays a deck', () {
      final insights = buildInsights(
        feed(
          hasCv: false,
          chosenPaths: 0,
          streak: const Streak(current: 5, longest: 5, days: []),
          thisWeek: week(
            tasksDone: 3,
            taskPoints: 9,
            applicationsAdded: 1,
            interviewsPractised: 1,
            documentsAdded: 1,
            scoreGained: 6,
          ),
          timeline: [
            entry(title: 'Late thing', inDays: -1),
            entry(title: 'Today thing', inDays: 0),
          ],
          skillGap: const [SkillGap(id: 's', name: 'SQL', importance: 'core')],
          roadmap: const RoadmapSummary(
            done: 1,
            total: 5,
            overdue: 0,
            nextTaskId: 't1',
            nextTaskTitle: 'Learn joins',
          ),
        ),
      );
      expect(insights.length, lessThanOrEqualTo(5));
    });
  });

  group('streaks are never a punishment', () {
    test('a run is celebrated once it is worth celebrating', () {
      final insights = buildInsights(
        feed(streak: const Streak(current: 4, longest: 9, days: [])),
      );
      final streak = insights.firstWhere((i) => i.id == 'streak');
      expect(streak.tone, InsightTone.positive);
      expect(streak.title, '4 days in a row');
      expect(streak.body, contains('9 days'));
    });

    test('a two-day run is not yet a thing worth saying', () {
      final insights = buildInsights(
        feed(streak: const Streak(current: 2, longest: 2, days: [])),
      );
      expect(idsOf(insights), isNot(contains('streak')));
    });

    test('a broken run says what to do, not what was lost', () {
      final insights = buildInsights(
        feed(streak: const Streak(current: 0, longest: 7, days: [])),
      );
      final card = insights.firstWhere((i) => i.id == 'streak-restart');
      expect(card.tone, isNot(InsightTone.urgent));
      for (final blame in ['lost', 'failed', 'broke', 'missed']) {
        expect(
          card.body.toLowerCase(),
          isNot(contains(blame)),
          reason: 'a broken streak must not say "$blame"',
        );
      }
    });
  });

  group('momentum', () {
    test('a better week than the last is said out loud', () {
      final insights = buildInsights(
        feed(
          thisWeek: week(tasksDone: 3, taskPoints: 9, scoreGained: 4),
          lastWeek: week(tasksDone: 1, taskPoints: 2, scoreGained: 1),
        ),
      );
      final card = insights.firstWhere((i) => i.id == 'momentum-up');
      expect(card.body, contains('3 roadmap steps'));
      expect(card.body, contains('against 1 last week'));
    });

    test('a quiet week is only mentioned when the last one was not', () {
      final afterABusyWeek = buildInsights(
        feed(lastWeek: week(tasksDone: 4, taskPoints: 10, scoreGained: 3)),
      );
      expect(idsOf(afterABusyWeek), contains('momentum-quiet'));

      // Two quiet weeks in a row is not a moment to tell somebody off twice.
      final afterAQuietWeek = buildInsights(feed());
      expect(idsOf(afterAQuietWeek), isNot(contains('momentum-quiet')));
    });
  });

  group('year mode is a hard filter, not a tone', () {
    test('a first-year is never told about a late follow-up', () {
      final insights = buildInsights(
        feed(
          mode: YearMode.explore,
          timeline: [
            entry(
              title: 'Follow up with bKash',
              inDays: -3,
              kind: TimelineKind.application,
            ),
          ],
        ),
      );
      expect(idsOf(insights), isNot(contains('overdue')));
    });

    test('a first-year still hears about a late roadmap step', () {
      final insights = buildInsights(
        feed(
          mode: YearMode.explore,
          timeline: [entry(title: 'Try a free SQL course', inDays: -3)],
        ),
      );
      expect(insights.first.id, 'overdue');
    });

    test('nobody junior is shown the CV-is-the-problem card', () {
      final counts = const ApplicationCounts({TackStatus.applied: 9});
      for (final mode in [YearMode.explore, YearMode.build]) {
        expect(
          idsOf(buildInsights(feed(mode: mode, counts: counts))),
          isNot(contains('no-callbacks')),
          reason: '${mode.name} must not be shown a job-hunt diagnosis',
        );
      }
      expect(
        idsOf(buildInsights(feed(mode: YearMode.launch, counts: counts))),
        contains('no-callbacks'),
      );
    });

    test('a junior year never has applications counted out loud at them', () {
      final busy = week(
        tasksDone: 1,
        taskPoints: 2,
        applicationsAdded: 3,
        scoreGained: 2,
      );
      final insights = buildInsights(
        feed(mode: YearMode.build, thisWeek: busy),
      );
      final card = insights.firstWhere((i) => i.id == 'momentum-up');
      expect(card.body, isNot(contains('sent')));
      expect(card.body, contains('1 roadmap step'));
    });
  });

  group('the skill gap', () {
    test('core skills are named, and only core skills', () {
      final insights = buildInsights(
        feed(
          skillGap: const [
            SkillGap(id: '1', name: 'SQL', importance: 'core'),
            SkillGap(id: '2', name: 'Power BI', importance: 'core'),
            SkillGap(id: '3', name: 'Public speaking', importance: 'nice'),
          ],
        ),
      );
      final card = insights.firstWhere((i) => i.id == 'skill-gap');
      expect(card.title, '2 core skills to go');
      expect(card.body, contains('SQL, Power BI'));
      expect(card.body, isNot(contains('Public speaking')));
    });

    test('a gap of only nice-to-haves is not raised as a gap', () {
      final insights = buildInsights(
        feed(
          skillGap: const [
            SkillGap(id: '3', name: 'Public speaking', importance: 'nice'),
          ],
        ),
      );
      expect(idsOf(insights), isNot(contains('skill-gap')));
    });
  });

  group('the next roadmap step', () {
    test('is suggested when nothing is late', () {
      final insights = buildInsights(
        feed(
          roadmap: const RoadmapSummary(
            done: 2,
            total: 8,
            overdue: 0,
            activeMilestone: 'Learn the tools',
            nextTaskId: 't1',
            nextTaskTitle: 'Finish the SQL course',
            nextTaskPoints: 5,
            nextTaskMinutes: 90,
          ),
        ),
      );
      final card = insights.firstWhere((i) => i.id == 'next-task');
      expect(card.title, 'Finish the SQL course');
      expect(card.body, 'Learn the tools · about 90 minutes · +5 points');
    });

    test('gives way to anything already late', () {
      final insights = buildInsights(
        feed(
          timeline: [entry(title: 'Ship the project', inDays: -2)],
          roadmap: const RoadmapSummary(
            done: 2,
            total: 8,
            overdue: 1,
            nextTaskId: 't1',
            nextTaskTitle: 'Finish the SQL course',
          ),
        ),
      );
      expect(idsOf(insights), isNot(contains('next-task')));
    });
  });
}
