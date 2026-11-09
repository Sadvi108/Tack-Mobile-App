import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/coach/application/coach_routes.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/routing/routes.dart';

/// The route ids as the server declares them (`COACH_ROUTES`).
List<String> serverRoutes() {
  final ts = File(
    '../supabase/functions/_shared/coach/actions.ts',
  ).readAsStringSync();
  final block = RegExp(
    r'COACH_ROUTES = \[([^\]]*)\]',
  ).firstMatch(ts)!.group(1)!;
  return [
    for (final m in RegExp(r'"([a-z_]+)"').allMatches(block)) m.group(1)!,
  ];
}

CoachAction chip(String route, {String? slug}) =>
    CoachAction(route: route, label: 'Open it', slug: slug);

void main() {
  test('the app knows every route id the server can send', () {
    final ids = serverRoutes();
    expect(ids.length, 12);
    expect(CoachAction.routes, ids.toSet());
    for (final id in ids) {
      expect(
        coachDestination(chip(id, slug: 'data-analyst')),
        isNotNull,
        reason: id,
      );
    }
  });

  test('each chip opens the screen C7.2 names', () {
    expect(coachDestination(chip('interview')), Routes.interview);
    expect(coachDestination(chip('practice')), Routes.interviewReview);
    expect(coachDestination(chip('analyser')), Routes.analyser);
    expect(coachDestination(chip('cv_check')), Routes.cvCheck);
    expect(coachDestination(chip('cv_builder')), Routes.cvBuilder);
    expect(coachDestination(chip('roadmap')), Routes.roadmap);
    expect(coachDestination(chip('radar')), Routes.radar);
    expect(coachDestination(chip('score')), Routes.score);
    expect(coachDestination(chip('paths')), Routes.paths);
    expect(coachDestination(chip('applications')), Routes.applications);
    expect(coachDestination(chip('profile')), Routes.profile);
  });

  test('path opens its guide, or every path without a good slug', () {
    expect(
      coachDestination(chip('path', slug: 'data-analyst')),
      Routes.path('data-analyst'),
    );
    expect(coachDestination(chip('path')), Routes.paths);
    expect(coachDestination(chip('path', slug: '../admin')), Routes.paths);
  });

  test('an unknown route draws no chip', () {
    expect(coachDestination(chip('teleport')), isNull);
  });

  test('tab destinations switch tabs; the rest are pushed', () {
    for (final id in ['roadmap', 'radar', 'applications', 'profile']) {
      expect(
        Routes.isTabLocation(coachDestination(chip(id))!),
        isTrue,
        reason: id,
      );
    }
    for (final id in ['interview', 'practice', 'score', 'paths']) {
      expect(
        Routes.isTabLocation(coachDestination(chip(id))!),
        isFalse,
        reason: id,
      );
    }
  });
}
