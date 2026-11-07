import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';
import 'package:tack/features/score/data/readiness.dart';
import 'package:tack/routing/router.dart';

/// Every location the app writes, checked against the real route tree.
///
/// A link to a location nothing declares lands on "That screen does not
/// exist". A link that resolves in the wrong place flips the tab under the
/// student or leaves back with nowhere to go. Both are invisible until tapped.
void main() {
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
}
