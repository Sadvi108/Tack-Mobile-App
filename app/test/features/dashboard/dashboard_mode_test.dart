import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/applications/data/application_repository.dart';
import 'package:tack/features/dashboard/application/next_actions.dart';
import 'package:tack/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tack/features/dashboard/presentation/widgets.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_repository.dart';
import 'package:tack/features/roadmap/data/roadmap_models.dart';
import 'package:tack/features/roadmap/data/roadmap_repository.dart';
import 'package:tack/features/score/data/readiness.dart';
import 'package:tack/features/score/data/score_repository.dart';

import '../../helpers.dart';

Profile profileIn(YearMode mode, int year) => Profile(
      id: 'u1',
      fullName: 'Rafiq Hossain',
      yearOfStudy: year,
      yearsTotal: 4,
      mode: mode,
      onboardingCompletedAt: DateTime(2026, 1, 1),
    );

ReadinessScore scoreFor(YearMode mode, int total) => ReadinessScore(
      total: total,
      mode: mode,
      delta: 0,
      computedAt: DateTime(2026, 8, 25),
      components: const [
        ScoreComponent(key: 'skills', earned: 4, max: 16, ratio: 0.25),
        ScoreComponent(key: 'application_activity', earned: 0, max: 0, ratio: 0),
      ],
    );

List<Override> overridesFor(YearMode mode, int year, {int total = 30}) => [
      profileProvider.overrideWith((ref) async => profileIn(mode, year)),
      readinessProvider.overrideWith((ref) async => scoreFor(mode, total)),
      weekChangeProvider.overrideWith((ref) async => 4),
      cohortProvider.overrideWith((ref) async => null),
      scoreTrendProvider.overrideWith((ref) async => const <ReadinessScore>[]),
      roadmapsProvider.overrideWith((ref) async => const <Roadmap>[]),
      nextActionsProvider.overrideWith((ref) async => const <NextAction>[]),
      applicationCountsProvider.overrideWith((ref) async => ApplicationCounts.empty),
      upcomingApplicationsProvider.overrideWith((ref) async => const <JobApplication>[]),
    ];

String allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' ');

void main() {
  setUpAll(loadTackFonts);

  testWidgets('explore mode hides the application funnel entirely', (tester) async {
    await pumpAt(tester, const DashboardScreen(),
        size: const Size(360, 800), overrides: overridesFor(YearMode.explore, 1));
    await tester.pump();

    expect(find.byType(ApplicationFunnel), findsNothing,
        reason: 'a first-year is never shown a funnel');
    expect(find.text('First year · explore'), findsOneWidget);
  });

  testWidgets('explore mode never uses deadline or apply language', (tester) async {
    await pumpAt(tester, const DashboardScreen(),
        size: const Size(360, 800), overrides: overridesFor(YearMode.explore, 1));
    await tester.pump();

    final text = allText(tester).toLowerCase();
    for (final banned in ['deadline', 'apply', 'application']) {
      expect(text.contains(banned), isFalse,
          reason: 'explore mode must not say "$banned"');
    }
    expect(text.contains('explore'), isTrue);
  });

  testWidgets('final year shows the funnel and leads with dates', (tester) async {
    await pumpAt(tester, const DashboardScreen(),
        size: const Size(360, 800), overrides: overridesFor(YearMode.launch, 4));
    await tester.pump();

    expect(find.byType(ApplicationFunnel), findsOneWidget);
    expect(find.text('Next seven days'), findsOneWidget);
    expect(find.text('Final year · launch'), findsOneWidget);
  });

  testWidgets('build and prove modes show no funnel', (tester) async {
    for (final (mode, year) in [(YearMode.build, 2), (YearMode.prove, 3)]) {
      await pumpAt(tester, const DashboardScreen(),
          size: const Size(360, 800), overrides: overridesFor(mode, year));
      await tester.pump();
      expect(find.byType(ApplicationFunnel), findsNothing,
          reason: '${mode.name} mode must not show a funnel');
    }
  });

  testWidgets('a first-year is never compared against final-years', (tester) async {
    await pumpAt(tester, const DashboardScreen(),
        size: const Size(360, 800), overrides: overridesFor(YearMode.explore, 1));
    await tester.pump();

    expect(allText(tester).contains('final-years'), isFalse);
  });

  testWidgets('the dashboard lays out at the 360px minimum without overflow',
      (tester) async {
    await pumpAt(tester, const DashboardScreen(),
        size: const Size(360, 640), overrides: overridesFor(YearMode.launch, 4));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
