import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart' show TackStatus;
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/dashboard/application/insights.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';
import 'package:tack/features/score/data/readiness.dart';
import 'package:tack/features/toolkit/application/toolkit_tools.dart';
import 'package:tack/features/analyser/presentation/analyser_screen.dart';
import 'package:tack/features/applications/presentation/applications_screen.dart';
import 'package:tack/features/coach/application/coach_routes.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/features/coach/presentation/coach_screen.dart';
import 'package:tack/features/cv_builder/presentation/cv_builder_screen.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';
import 'package:tack/features/paths/presentation/path_detail_screen.dart';
import 'package:tack/features/paths/presentation/paths_screen.dart';
import 'package:tack/features/profile/presentation/profile_screen.dart';
import 'package:tack/features/radar/presentation/radar_screen.dart';
import 'package:tack/features/roadmap/presentation/roadmap_screen.dart';
import 'package:tack/features/score/presentation/score_screen.dart';
import 'package:tack/features/toolkit/presentation/toolkit_screen.dart';
import 'package:tack/features/vault/presentation/cv_check_entry_screen.dart';
import 'package:tack/features/vault/presentation/vault_screen.dart';
import 'package:tack/routing/router.dart';

import '../features/dashboard/insights_test.dart' as fixture show feed, today;

/// Every location the app writes, checked against the real route tree.
///
/// A link to a location nothing declares lands on "That screen does not
/// exist". A link that resolves in the wrong place flips the tab under the
/// student or leaves back with nowhere to go. Both are invisible until tapped.
void main() {
  // Before the router: GoRouter sets up a binding, and the widget tests
  // below need it to be the test one.
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: root,
    routes: tackRoutes(root: root),
  );
  tearDownAll(router.dispose);

  RouteMatchList match(String location) =>
      router.configuration.findMatch(Uri.parse(location));

  /// The shell branch a location shows inside, or null when it covers the
  /// tab bar (declared outside the shell, or on the root navigator).
  int? branchOf(String location) {
    final matches = match(location).matches;
    final first = matches.first;
    if (first is! ShellRouteMatch) return null;
    // A route on the root navigator under a branch (one application) is
    // matched after the shell, not inside it: it covers the bar.
    if (matches.length > 1) return null;
    var leaf = first.matches.last;
    while (leaf is ShellRouteMatch) {
      leaf = leaf.matches.last;
    }
    final route = leaf.route;
    if (route is GoRoute && route.parentNavigatorKey == root) return null;
    final shell = first.route as StatefulShellRoute;
    final top = first.matches.first.route;
    return shell.branches.indexWhere((b) => b.routes.contains(top));
  }

  /// The screen the real tree builds for [location], without building it:
  /// the matched route's own builder, called with the state it would get.
  Widget screenAt(BuildContext context, String location) {
    final matches = match(location);
    final leaf = matches.last;
    final route = leaf.route;
    return route.builder!(
      context,
      leaf.buildState(router.configuration, matches),
    );
  }

  void resolves(String location) {
    final result = match(location);
    expect(result.isError, isFalse, reason: location);
    expect(result.matches, isNotEmpty, reason: location);
  }

  final constants = <String>[
    Routes.home,
    Routes.roadmap,
    Routes.radar,
    Routes.applications,
    Routes.application('x'),
    Routes.toolkit,
    Routes.vault,
    Routes.profile,
    Routes.interview,
    Routes.interviewReview,
    Routes.coach,
    Routes.analyser,
    Routes.cvCheck,
    Routes.cvCheckFor('x'),
    Routes.cvBuilder,
    Routes.paths,
    Routes.path('x'),
    Routes.score,
    Routes.notifications,
    Routes.settings,
    Routes.settingsSync,
  ];

  test('every route constant and helper resolves', () {
    constants.forEach(resolves);
  });

  test('the documents keep the Toolkit tab lit, applications keep Radar', () {
    expect(branchOf(Routes.toolkit), 3);
    expect(branchOf(Routes.vault), 3);
    expect(branchOf(Routes.radar), 2);
    expect(branchOf(Routes.applications), 2);
    expect(branchOf(Routes.home), 0);
    expect(branchOf(Routes.roadmap), 1);
    expect(branchOf(Routes.profile), 4);
  });

  test('tools and details cover the tab bar', () {
    for (final location in [
      Routes.interview,
      Routes.interviewReview,
      Routes.coach,
      Routes.analyser,
      Routes.cvCheck,
      Routes.cvCheckFor('x'),
      Routes.cvBuilder,
      Routes.application('x'),
    ]) {
      expect(branchOf(location), isNull, reason: location);
    }
  });

  test('a tab location is exactly a location inside a branch', () {
    for (final location in constants) {
      expect(
        Routes.isTabLocation(location),
        branchOf(location) != null,
        reason: location,
      );
    }
  });

  group('locations the data layer writes', () {
    test('every readiness component', () {
      for (final key in [
        'profile_completeness',
        'academic',
        'skills',
        'projects',
        'activities',
        'experience',
        'certifications',
        'cv_quality',
        'interview_practice',
        'application_activity',
        'roadmap_progress',
        'unknown',
      ]) {
        resolves(ScoreComponent(key: key, earned: 0, max: 1, ratio: 0).route);
      }
    });

    test('every notification type', () {
      for (final type in [
        'analysis_ready',
        'cv_parsed',
        'deadline',
        'score_changed',
        'step_due',
        'weekly_brief',
        'general',
      ]) {
        resolves(
          TackNotification(
            id: 'n',
            type: type,
            title: 't',
            createdAt: DateTime(2026),
          ).route,
        );
      }
    });

    test('every suggestion on Home, over a full fixture', () {
      final timeline = [
        for (final (days, route) in [
          (-3, Routes.roadmap),
          (0, Routes.application('a1')),
          (2, Routes.roadmap),
        ])
          TimelineEntry(
            kind: TimelineKind.task,
            id: 't$days',
            title: 'Step',
            on: fixture.today.add(Duration(days: days)),
            route: route,
            isOverdue: days < 0,
          ),
      ];
      final ids = <String>{};
      for (final counts in const [
        ApplicationCounts({TackStatus.applied: 9}),
        ApplicationCounts({TackStatus.interview: 2}),
      ]) {
        for (final hasCv in [true, false]) {
          for (final chosenPaths in [0, 1]) {
            final insights = buildInsights(
              fixture.feed(
                hasCv: hasCv,
                chosenPaths: chosenPaths,
                counts: counts,
                timeline: timeline,
                skillGap: const [
                  SkillGap(id: 's', name: 'SQL', importance: 'core'),
                ],
                roadmap: const RoadmapSummary(
                  done: 1,
                  total: 5,
                  overdue: 0,
                  nextTaskId: 't1',
                  nextTaskTitle: 'Learn joins',
                ),
              ),
              limit: 100,
            );
            for (final insight in insights) {
              ids.add(insight.id);
              if (insight.route case final route?) resolves(route);
            }
          }
        }
      }
      expect(
        ids,
        containsAll([
          'overdue',
          'due-today',
          'interview-stage',
          'no-cv',
          'no-path',
          'skill-gap',
          'no-callbacks',
        ]),
      );
    });

    test('every Toolkit tool', () {
      for (final tool in ToolkitTool.values) {
        resolves(tool.route);
      }
    });

    test('every place a brief item may point', () {
      for (final route in [
        Routes.roadmap,
        Routes.interview,
        Routes.radar,
        Routes.application('0b0a7f2e-6a43-4c1e-9d55-2f1a3c4b5d6e'),
      ]) {
        final item = BriefItem.fromJson({
          'title': 't',
          'why': 'w',
          'route': route,
        });
        expect(item, isNotNull, reason: route);
        resolves(item!.route);
      }
    });
  });

  // Every place a chip, a card or a suggestion can take a student, followed
  // to the screen the real tree builds there.
  group('the screen at the end of every link', () {
    late BuildContext context;

    Future<void> grabContext(WidgetTester tester) => tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    );

    testWidgets('every coach chip opens a real screen', (tester) async {
      await grabContext(tester);
      const expected = <String, Type>{
        'interview': InterviewScreen,
        'practice': InterviewScreen,
        'analyser': AnalyserScreen,
        'cv_check': CvCheckEntryScreen,
        'cv_builder': CvBuilderScreen,
        'roadmap': RoadmapScreen,
        'radar': RadarScreen,
        'score': ScoreScreen,
        'paths': PathsScreen,
        'path': PathDetailScreen,
        'applications': ApplicationsScreen,
        'profile': ProfileScreen,
      };
      for (final MapEntry(key: id, value: screen) in expected.entries) {
        final destination = coachDestination(
          CoachAction(route: id, label: 'x', slug: 'data-analyst'),
        );
        expect(destination, isNotNull, reason: id);
        resolves(destination!);
        expect(screenAt(context, destination).runtimeType, screen, reason: id);
      }
      // The CV check chip opens the entry, which picks the CV itself.
      expect(
        coachDestination(const CoachAction(route: 'cv_check', label: 'x')),
        Routes.cvCheck,
      );
      // Practise again is the review route, which the screen reads from its
      // own matched location (Appendix B, ruling 4).
      expect(
        match(
          coachDestination(const CoachAction(route: 'practice', label: 'x'))!,
        ).last.matchedLocation,
        Routes.interviewReview,
      );
      // A bad slug falls back to the list rather than a broken page.
      expect(
        coachDestination(
          const CoachAction(route: 'path', label: 'x', slug: '../etc'),
        ),
        Routes.paths,
      );
      expect(coachDestination(const CoachAction(route: 'x', label: 'x')), null);
    });

    testWidgets('every Toolkit card opens its screen', (tester) async {
      await grabContext(tester);
      const expected = <ToolkitTool, Type>{
        ToolkitTool.interview: InterviewScreen,
        ToolkitTool.practiseAgain: InterviewScreen,
        ToolkitTool.analyser: AnalyserScreen,
        ToolkitTool.cvCheck: CvCheckEntryScreen,
        ToolkitTool.cvBuilder: CvBuilderScreen,
        ToolkitTool.documents: VaultScreen,
        ToolkitTool.coach: CoachScreen,
      };
      for (final MapEntry(key: tool, value: screen) in expected.entries) {
        expect(
          screenAt(context, tool.route).runtimeType,
          screen,
          reason: tool.name,
        );
      }
      expect(screenAt(context, Routes.toolkit), isA<ToolkitScreen>());
    });

    testWidgets('the suggestions that point at tools open them', (
      tester,
    ) async {
      await grabContext(tester);
      final insights = buildInsights(
        fixture.feed(
          counts: const ApplicationCounts({TackStatus.interview: 1}),
        ),
        limit: 100,
      );
      final interview = insights.firstWhere((i) => i.id == 'interview-stage');
      expect(screenAt(context, interview.route!), isA<InterviewScreen>());

      final noCallbacks = buildInsights(
        fixture.feed(counts: const ApplicationCounts({TackStatus.applied: 9})),
        limit: 100,
      ).firstWhere((i) => i.id == 'no-callbacks');
      expect(screenAt(context, noCallbacks.route!), isA<CvCheckEntryScreen>());
    });
  });
}
