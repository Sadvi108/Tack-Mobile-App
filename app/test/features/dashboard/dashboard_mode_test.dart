import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/applications/data/application_repository.dart';
import 'package:tack/features/dashboard/application/next_actions.dart';
import 'package:tack/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tack/features/dashboard/presentation/widgets.dart';
import 'package:tack/features/paths/data/path_repository.dart';
import 'package:tack/features/vault/data/document_models.dart';
import 'package:tack/features/vault/data/document_repository.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';
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
    ScoreComponent(key: 'projects', earned: 0, max: 10, ratio: 0),
    ScoreComponent(key: 'cv_quality', earned: 0, max: 13, ratio: 0),
    // Weighted zero in this mode, so it is not one of the areas being counted.
    ScoreComponent(key: 'application_activity', earned: 0, max: 0, ratio: 0),
  ],
);

List<Override> overridesFor(
  YearMode mode,
  int year, {
  int total = 30,
  // The set-up state is a parameter rather than a second override of the same
  // providers: overriding one provider twice in the same list is ambiguous,
  // and the composed dashboard provider silently failed to resolve when it was.
  List<TackDocument> documents = const [],
  List<ChosenPath> paths = const [],
  ApplicationCounts counts = ApplicationCounts.empty,
}) => [
  // A widget test must not open the on-device database, and the outbox
  // has its own tests — this one is about what each mode renders.
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  notificationsProvider.overrideWith((ref) async => const <TackNotification>[]),
  profileProvider.overrideWith((ref) async => profileIn(mode, year)),
  readinessProvider.overrideWith((ref) async => scoreFor(mode, total)),
  weekChangeProvider.overrideWith((ref) async => 4),
  cohortProvider.overrideWith((ref) async => null),
  scoreTrendProvider.overrideWith((ref) async => const <ReadinessScore>[]),
  roadmapsProvider.overrideWith((ref) async => const <Roadmap>[]),
  nextActionsProvider.overrideWith((ref) async => const <NextAction>[]),
  applicationCountsProvider.overrideWith((ref) async => counts),
  upcomingApplicationsProvider.overrideWith(
    (ref) async => const <JobApplication>[],
  ),
  // The dashboard composes these two as well, and a widget test must not let
  // either reach the network to find that out.
  documentsProvider.overrideWith((ref) async => documents),
  chosenPathsProvider.overrideWith((ref) async => paths),
];

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

  testWidgets('explore mode hides the application funnel entirely', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const DashboardScreen(),
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.explore, 1),
    );
    await tester.pump();

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
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.explore, 1),
    );
    await tester.pump();

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
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.launch, 4),
    );
    await tester.pump();

    expect(find.byType(ApplicationFunnel), findsOneWidget);
    expect(find.text('Next seven days'), findsOneWidget);
    expect(find.text('Final year · launch'), findsOneWidget);
  });

  testWidgets('build and prove modes show no funnel', (tester) async {
    for (final (mode, year) in [(YearMode.build, 2), (YearMode.prove, 3)]) {
      await pumpAt(
        tester,
        const DashboardScreen(),
        size: const Size(360, 800),
        overrides: overridesFor(mode, year),
      );
      await tester.pump();
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
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.explore, 1),
    );
    await tester.pump();

    expect(allText(tester).contains('final-years'), isFalse);
  });

  testWidgets('the dashboard lays out at the 360px minimum without overflow', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const DashboardScreen(),
      size: const Size(360, 640),
      overrides: overridesFor(YearMode.launch, 4),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('every mode gets the same five destinations', (tester) async {
    // The tab bar used to change with the year. It no longer does: a student's
    // app should not change shape underneath them between one September and
    // the next, and year-awareness lives in what each screen leads with.
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
      await tester.pump();

      for (final label in [
        'Home',
        'Roadmap',
        'Application',
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

  testWidgets('the five tabs fit at the 360px minimum', (tester) async {
    // Five labels across 360px is the tightest the bar ever gets, and
    // "Application" is the longest of them. An overflow here is a layout
    // failure the test framework reports as an exception.
    await pumpAt(
      tester,
      const DashboardScreen(),
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.explore, 1),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final label in [
      'Home',
      'Roadmap',
      'Application',
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

  testWidgets('a student who has just signed up is told what to do first', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const DashboardScreen(),
      size: const Size(360, 800),
      overrides: overridesFor(YearMode.launch, 4),
    );
    await tester.pumpAndSettle();

    expect(find.text('DO THIS FIRST'), findsOneWidget);
    expect(find.text('Upload your CV'), findsOneWidget);
    expect(find.text('Pick a target job'), findsOneWidget);

    // One to-do list at a time: the ranked suggestions would compete with the
    // three things that actually have to happen first.
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
        documents: [
          TackDocument(
            id: 'd1',
            type: DocumentType.cv,
            title: 'CV',
            storagePath: 'users/u/cv/d1',
            status: DocumentStatus.ready,
            createdAt: DateTime(2026),
          ),
        ],
        paths: const [ChosenPath(pathId: 'p1', isPrimary: true)],
        counts: const ApplicationCounts({TackStatus.applied: 2}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DO THIS FIRST'), findsNothing);
    expect(find.text('Your next three actions'), findsOneWidget);
  });

  testWidgets('the score is explained, not just stated', (tester) async {
    await pumpAt(
      tester,
      const DashboardScreen(),
      // Tall on purpose: a lazy ListView never builds what is below the fold,
      // so a presence assertion at 800px would be testing the scroll position.
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
}
