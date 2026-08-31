import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/dashboard/data/dashboard_repository.dart';
import 'package:tack/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tack/features/dashboard/presentation/insight_deck.dart';
import 'package:tack/features/dashboard/presentation/path_fit_card.dart';
import 'package:tack/features/dashboard/presentation/progress_card.dart';
import 'package:tack/features/dashboard/presentation/streak_card.dart';
import 'package:tack/features/dashboard/presentation/timeline_card.dart';
import 'package:tack/features/dashboard/presentation/widgets.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/score/data/readiness.dart';

import '../../helpers.dart';

final today = DateTime(2026, 8, 26); // a Wednesday

Profile profileIn(YearMode mode, int year, {String? targetRole}) => Profile(
  id: 'u1',
  fullName: 'Rafiq Hossain',
  yearOfStudy: year,
  yearsTotal: 4,
  mode: mode,
  targetRole: targetRole,
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

ReadinessScore scoreFor(YearMode mode, int total) => ReadinessScore(
  total: total,
  mode: mode,
  delta: 0,
  computedAt: DateTime(2026, 8, 25),
  components: const [
    ScoreComponent(key: 'skills', earned: 4, max: 16, ratio: 0.25),
    ScoreComponent(key: 'projects', earned: 0, max: 10, ratio: 0),
    ScoreComponent(key: 'cv_quality', earned: 0, max: 13, ratio: 0),
    // Weighted zero in this mode, so it is not one of the areas being counted.
    ScoreComponent(key: 'application_activity', earned: 0, max: 0, ratio: 0),
  ],
);

/// One feed snapshot, the way the database would send it.
///
/// The screen reads exactly one provider now, so a widget test builds one
/// object rather than stubbing thirteen — which is most of the reason the new
/// cards are testable at all.
DashboardFeed feedFor(
  YearMode mode,
  int year, {
  int total = 30,
  bool hasCv = false,
  int chosenPaths = 0,
  int availablePaths = 10,
  String? targetRole,
  ApplicationCounts counts = ApplicationCounts.empty,
  Streak streak = Streak.empty,
  List<TimelineEntry> timeline = const [],
  List<TrendPoint> trend = const [],
  List<SkillGap> skillGap = const [],
  String? primaryPathTitle,
  List<FollowedPath> following = const [],
  RoadmapSummary roadmap = RoadmapSummary.empty,
  WeekSummary thisWeek = WeekSummary.empty,
  WeekSummary lastWeek = WeekSummary.empty,
  int unread = 0,
}) => DashboardFeed(
  today: today,
  profile: profileIn(mode, year, targetRole: targetRole),
  score: scoreFor(mode, total),
  weekChange: 4,
  streak: streak,
  thisWeek: thisWeek,
  lastWeek: lastWeek,
  trend: trend,
  roadmap: roadmap,
  counts: counts,
  timeline: timeline,
  skillGap: skillGap,
  skillsHeld: 3,
  skillsAsked: 8,
  cohortAverage: null,
  cohortSize: null,
  chosenPaths: chosenPaths,
  availablePaths: availablePaths,
  primaryPathTitle: primaryPathTitle,
  primaryPathSlug: primaryPathTitle == null ? null : 'data-analyst',
  following: following,
  documentCount: hasCv ? 1 : 0,
  hasCv: hasCv,
  unreadNotifications: unread,
);

List<Override> overridesFor(YearMode mode, int year, {DashboardFeed? feed}) => [
  // A widget test must not open the on-device database, and the outbox has
  // its own tests — this one is about what each mode renders.
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  dashboardFeedProvider.overrideWith((ref) async => feed ?? feedFor(mode, year)),
];

TimelineEntry entry({
  required String title,
  required int inDays,
  TimelineKind kind = TimelineKind.task,
  String? subtitle,
}) => TimelineEntry(
  kind: kind,
  id: 't-$title',
  title: title,
  subtitle: subtitle,
  on: today.add(Duration(days: inDays)),
  route: '/roadmap',
  isOverdue: inDays < 0,
);

String allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' ');

/// The dashboard's own words, without the navigation underneath it.
///
/// The five tabs are the same in every mode, so a first-year's screen carries
/// a tab labelled "Application" whatever their year. That is furniture — a
/// permanent destination's name — and it is not the dashboard telling a
/// first-year to go and apply for things. The language rule is about what the
/// screen says; it is checked here on the body, and the tab bar has its own
/// test below.
String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.byType(Text),
      ),
    )
    .where((t) => !TackTabs.all.any((tab) => tab.label == t.data))
    .map((t) => t.data ?? '')
    .join(' ');

void main() {
  setUpAll(loadTackFonts);

  group('what each year mode is shown', () {
    testWidgets('explore mode hides the application funnel entirely', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 800),
        overrides: overridesFor(YearMode.explore, 1),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ApplicationFunnel),
        findsNothing,
        reason: 'a first-year is never shown a funnel',
      );
      expect(find.text('First year · explore'), findsOneWidget);
    });

    testWidgets('explore mode never uses deadline or apply language', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(
          YearMode.explore,
          1,
          // Job-shaped dates on the feed on purpose: the filter has to be in
          // the screen, not in what the fixture happens to contain.
          feed: feedFor(
            YearMode.explore,
            1,
            timeline: [
              entry(
                title: 'Follow up with bKash',
                inDays: 2,
                kind: TimelineKind.application,
              ),
              entry(
                title: 'Applications close',
                inDays: 4,
                kind: TimelineKind.closing,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = bodyText(tester).toLowerCase();
      for (final banned in ['deadline', 'apply', 'application']) {
        expect(
          text.contains(banned),
          isFalse,
          reason: 'explore mode must not say "$banned"',
        );
      }
      expect(text.contains('explore'), isTrue);
    });

    testWidgets('final year shows the funnel and leads with dates', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ApplicationFunnel), findsOneWidget);
      expect(find.text('Next seven days'), findsOneWidget);
      expect(find.text('Final year · launch'), findsOneWidget);
    });

    testWidgets('build and prove modes show no funnel', (tester) async {
      for (final (mode, year) in [(YearMode.build, 2), (YearMode.prove, 3)]) {
        await pumpAt(
          tester,
          const DashboardScreen(),
          size: const Size(360, 2400),
          overrides: overridesFor(mode, year),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(ApplicationFunnel),
          findsNothing,
          reason: '${mode.name} mode must not show a funnel',
        );
      }
    });

    testWidgets('a first-year is never compared against final-years', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.explore, 1),
      );
      await tester.pumpAndSettle();

      expect(allText(tester).contains('final-years'), isFalse);
    });
  });

  group('layout', () {
    testWidgets('the dashboard lays out at the 360px minimum without overflow', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 640),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a full dashboard still fits at 360px', (tester) async {
      // Every card at once, each with content: this is the widest any of them
      // ever gets, and an overflow here is a layout failure the framework
      // reports as an exception.
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 3200),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            hasCv: true,
            chosenPaths: 1,
            primaryPathTitle: 'Data analyst',
            counts: const ApplicationCounts({
              TackStatus.applied: 6,
              TackStatus.assessment: 2,
            }),
            streak: Streak(
              current: 4,
              longest: 9,
              days: [for (var i = 0; i < 4; i++) today.subtract(Duration(days: i))],
            ),
            timeline: [
              entry(title: 'Finish the SQL course', inDays: -2),
              entry(title: 'Ship the dashboard project', inDays: 0),
              entry(
                title: 'Follow up with bKash',
                inDays: 3,
                kind: TimelineKind.application,
                subtitle: 'Data analyst · bKash',
              ),
            ],
            trend: [
              for (var i = 0; i < 8; i++)
                TrendPoint(
                  week: today.subtract(Duration(days: 7 * (8 - i))),
                  total: 12 + i * 3,
                ),
            ],
            skillGap: const [
              SkillGap(id: 's1', name: 'SQL', importance: 'core'),
              SkillGap(id: 's2', name: 'Power BI', importance: 'core'),
              SkillGap(id: 's3', name: 'Statistics', importance: 'important'),
            ],
            roadmap: const RoadmapSummary(
              done: 4,
              total: 11,
              overdue: 1,
              activeMilestone: 'Learn the tools',
            ),
            thisWeek: const WeekSummary(
              moves: 5,
              activeDays: 3,
              tasksDone: 3,
              taskPoints: 12,
              applicationsAdded: 1,
              interviewsPractised: 0,
              documentsAdded: 1,
              skillsAdded: 0,
              projectsAdded: 0,
              scoreGained: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('every mode gets the same five destinations', (tester) async {
      // The tab bar used to change with the year. It no longer does: a
      // student's app should not change shape underneath them between one
      // September and the next, and year-awareness lives in what each screen
      // leads with.
      for (final (mode, year) in [
        (YearMode.explore, 1),
        (YearMode.build, 2),
        (YearMode.prove, 3),
        (YearMode.launch, 4),
      ]) {
        await pumpAt(
          tester,
          const DashboardScreen(),
          size: const Size(360, 800),
          overrides: overridesFor(mode, year),
        );
        await tester.pumpAndSettle();

        for (final label in [
          'Home',
          'Roadmap',
          'Radar',
          'Vault',
          'Profile',
        ]) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: '$mode is missing the $label tab',
          );
        }
        expect(find.text('Paths'), findsNothing, reason: 'paths is not a tab');
      }
    });

    testWidgets('the coach is reachable from home in every mode', (
      tester,
    ) async {
      // It floats rather than taking a tab: five is the ceiling at 360px, and
      // asking a question is something a student does about what they are
      // looking at, not instead of it.
      for (final (mode, year) in [
        (YearMode.explore, 1),
        (YearMode.launch, 4),
      ]) {
        await pumpAt(
          tester,
          const DashboardScreen(),
          size: const Size(360, 800),
          overrides: overridesFor(mode, year),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Ask'),
          findsOneWidget,
          reason: '${mode.name} cannot reach the coach',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the five tabs fit at the 360px minimum', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 800),
        overrides: overridesFor(YearMode.explore, 1),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in [
        'Home',
        'Roadmap',
        'Radar',
        'Vault',
        'Profile',
      ]) {
        final size = tester.getSize(find.text(label));
        expect(
          size.width,
          lessThanOrEqualTo(360 / 5),
          reason: '$label is too wide',
        );
      }
    });
  });

  group('setting up', () {
    testWidgets('a student who has just signed up is told what to do first', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      expect(find.text('DO THIS FIRST'), findsOneWidget);
      expect(find.text('Upload your CV'), findsOneWidget);
      expect(find.text('Pick a target job'), findsOneWidget);

      // One to-do list at a time: the ranked suggestions would compete with
      // the things that actually have to happen first.
      expect(find.text('Your next three actions'), findsNothing);
    });

    testWidgets('once set up, the ranked actions take over', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            hasCv: true,
            chosenPaths: 1,
            counts: const ApplicationCounts({TackStatus.applied: 2}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DO THIS FIRST'), findsNothing);
      expect(find.text('Your next three actions'), findsOneWidget);
    });
  });

  group('the score', () {
    testWidgets('the score is explained, not just stated', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        // Tall on purpose: a lazy ListView never builds what is below the
        // fold, so a presence assertion at 800px would be testing the scroll
        // position.
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      expect(find.text('READINESS / 100'), findsOneWidget);
      // A number on its own is a verdict; the fraction is a to-do list. Three
      // components carry weight in this fixture and one of them is scored.
      expect(find.text('One of 3 areas have any score.'), findsOneWidget);
      expect(find.text('See the three  →'), findsOneWidget);
    });

    testWidgets('the ring settles on the real score, not part way', (
      tester,
    ) async {
      // The ring sweeps up to its value. A test that only pumped one frame
      // would assert on whatever number the curve happened to be passing
      // through, so this waits for the reveal to finish.
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      expect(find.text('30'), findsWidgets);
    });

    testWidgets('every mode says the score is private', (tester) async {
      for (final (mode, year) in [(YearMode.explore, 1), (YearMode.launch, 4)]) {
        await pumpAt(
          tester,
          const DashboardScreen(),
          size: const Size(360, 2400),
          overrides: overridesFor(mode, year),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Nothing here is public. Your score is only for you.'),
          findsOneWidget,
          reason: '$mode does not reassure the student',
        );
      }
    });
  });

  group('the live cards', () {
    testWidgets('a chosen path brings its skill gap with it', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 3200),
        overrides: overridesFor(
          YearMode.prove,
          3,
          feed: feedFor(
            YearMode.prove,
            3,
            hasCv: true,
            chosenPaths: 1,
            primaryPathTitle: 'Data analyst',
            skillGap: const [
              SkillGap(id: 's1', name: 'SQL', importance: 'core'),
              SkillGap(id: 's2', name: 'Power BI', importance: 'core'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PathFitCard), findsOneWidget);
      expect(find.text('Data analyst'), findsWidgets);
      expect(find.text('SQL'), findsOneWidget);
      expect(find.text('You have 3 of the 8 skills it asks for.'), findsOneWidget);
    });

    testWidgets('no chosen path means no target card', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.prove, 3),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PathFitCard), findsNothing);
    });

    testWidgets('a path you only follow is never called your target', (
      tester,
    ) async {
      // The bug this exists to stop: tapping Follow on Content writer while
      // browsing put "YOUR TARGET — Content writer" on the home screen of a
      // student whose profile said Backend developer. Following is not
      // choosing.
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            hasCv: true,
            chosenPaths: 1,
            following: const [
              FollowedPath(id: 'p-cw', title: 'Content writer', slug: 'content-writer'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PathFitCard), findsNothing);
      expect(find.text('YOUR TARGET'), findsNothing);
      expect(find.text('You are following Content writer'), findsOneWidget);
      expect(find.text('Make it my target'), findsOneWidget);
    });

    testWidgets('and the role they typed is used to point out the mismatch', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            hasCv: true,
            chosenPaths: 1,
            targetRole: 'Backend developer',
            following: const [
              FollowedPath(id: 'p-cw', title: 'Content writer', slug: 'content-writer'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = bodyText(tester);
      expect(text, contains('You told us you are aiming at Backend developer'));
    });

    testWidgets('with no path at all, their own words lead', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            hasCv: true,
            targetRole: 'Backend developer',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You said you want to be a Backend developer'),
        findsOneWidget,
      );
    });

    testWidgets('the career path count is never written into the copy', (
      tester,
    ) async {
      // "Ten real jobs" was true only until somebody added an eleventh.
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(
          YearMode.explore,
          1,
          feed: feedFor(YearMode.explore, 1, availablePaths: 14),
        ),
      );
      await tester.pumpAndSettle();

      final text = bodyText(tester);
      expect(text, contains('14 real jobs'));
      expect(text, isNot(contains('Ten real jobs')));
    });

    testWidgets('the streak is drawn from the days the student was active', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.build,
          2,
          feed: feedFor(
            YearMode.build,
            2,
            streak: Streak(
              current: 5,
              longest: 5,
              days: [
                for (var i = 0; i < 5; i++) today.subtract(Duration(days: i)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StreakCard), findsOneWidget);
      expect(find.text('SHOWING UP'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
      // A run at its own record is called out, and never as a loss.
      expect(find.text('Your best'), findsOneWidget);
    });

    testWidgets('a broken streak is stated without blame', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.build,
          2,
          feed: feedFor(
            YearMode.build,
            2,
            streak: const Streak(current: 0, longest: 9, days: []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = bodyText(tester).toLowerCase();
      expect(text.contains('lost'), isFalse);
      expect(text.contains('failed'), isFalse);
      expect(text.contains('broke'), isFalse);
      expect(
        find.text(
          'Your longest run is 9 days. Anything you add today starts the next one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dates a junior year is allowed to see still appear', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.build,
          2,
          feed: feedFor(
            YearMode.build,
            2,
            timeline: [
              entry(title: 'Finish the SQL course', inDays: 1),
              entry(title: 'Start the portfolio', inDays: 5),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TimelineCard), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Finish the SQL course'), findsOneWidget);
    });

    testWidgets('a late item is called late, in the card and in the heading', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2800),
        overrides: overridesFor(
          YearMode.launch,
          4,
          feed: feedFor(
            YearMode.launch,
            4,
            timeline: [entry(title: 'Send the cover letter', inDays: -3)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 late'), findsOneWidget);
      expect(find.text('3 days late'), findsOneWidget);
    });

    testWidgets('the trend card waits for two weeks before drawing a line', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.build, 2),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProgressCard), findsOneWidget);
      expect(
        find.text('Your line appears once there are two weeks to join up.'),
        findsOneWidget,
      );
    });
  });

  group('the suggestion deck', () {
    testWidgets('suggestions appear as a swipeable deck', (tester) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      // A brand-new final-year has no CV and no path, so both are suggested.
      expect(find.byType(InsightDeck), findsOneWidget);
      expect(find.text('Tack has not seen your CV'), findsOneWidget);
    });

    testWidgets('swiping the deck moves to the next suggestion', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(YearMode.launch, 4),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();

      expect(find.text('Choose a target job'), findsOneWidget);
    });

    testWidgets('a first-year is never suggested anything job-shaped', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 2400),
        overrides: overridesFor(
          YearMode.explore,
          1,
          feed: feedFor(
            YearMode.explore,
            1,
            counts: const ApplicationCounts({TackStatus.applied: 8}),
            timeline: [
              entry(
                title: 'Follow up with bKash',
                inDays: -2,
                kind: TimelineKind.application,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The feed carries eight sent applications and one late follow-up. A
      // first-year is told about neither.
      final text = bodyText(tester).toLowerCase();
      expect(text.contains('bkash'), isFalse);
      expect(text.contains('slipped past'), isFalse);
    });
  });
}
