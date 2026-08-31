import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/applications/data/application_repository.dart';
import 'package:tack/features/dashboard/data/dashboard_repository.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_repository.dart';
import 'package:tack/features/radar/data/listing.dart';
import 'package:tack/features/radar/data/radar_repository.dart';
import 'package:tack/features/radar/presentation/radar_screen.dart';

import '../../helpers.dart';

Listing listing({
  String id = 'l1',
  String title = 'Backend developer',
  int? fit = 75,
  int asks = 4,
  int have = 3,
  bool remote = false,
  List<String> matched = const ['Node.js', 'PostgreSQL', 'Docker'],
  List<String> missing = const ['React'],
  String? saved,
}) => Listing(
  id: id,
  source: 'careerjet',
  title: title,
  url: 'https://example.test/$id',
  applyUrl: 'https://example.test/$id',
  company: 'Acme',
  location: 'Dhaka',
  isRemote: remote,
  salary: 'BDT 60,000',
  fit: fit,
  asks: asks,
  have: have,
  matchedSkills: matched,
  missingSkills: missing,
  savedApplicationId: saved,
);

List<Override> overrides(RadarResult result, {int saved = 0}) => [
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  profileProvider.overrideWith(
    (ref) async => const Profile(
      id: 'u1',
      fullName: 'Rafiq Hossain',
      targetRole: 'Backend developer',
      mode: YearMode.launch,
    ),
  ),
  dashboardFeedProvider.overrideWith((ref) async => null),
  radarResultsProvider.overrideWith((ref) async => result),
  applicationCountsProvider.overrideWith(
    (ref) async => saved == 0
        ? ApplicationCounts.empty
        : ApplicationCounts({TackStatus.saved: saved}),
  ),
  applicationsProvider.overrideWith((ref, status) async => const []),
];

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  setUpAll(loadTackFonts);

  testWidgets('an opening leads with how well it fits', (tester) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(RadarResult(listings: [listing()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend developer'), findsWidgets);
    expect(find.text('75'), findsOneWidget);
    expect(find.text('3 of 4 skills. Missing React.'), findsOneWidget);
  });

  testWidgets('a listing with nothing to read scores nothing, not zero', (
    tester,
  ) async {
    // The distinction the whole card turns on. "0%" reads as "you are not good
    // enough"; the truth is that the posting never said what it wanted.
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(
        RadarResult(
          listings: [
            listing(
              title: 'Graduate programme',
              fit: null,
              asks: 0,
              have: 0,
              matched: const [],
              missing: const [],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
    expect(find.text('–'), findsOneWidget);
    expect(
      find.text(
        'This posting does not list what it asks for, so there is nothing '
        'to match against.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a saved opening says so instead of offering to save again', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(
        RadarResult(listings: [listing(saved: 'app-1')]),
        saved: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In your tracker'), findsOneWidget);
    expect(find.text('Save it'), findsNothing);
    expect(find.text('Tracking · 1'), findsOneWidget);
  });

  testWidgets('a board that is switched off is said out loud', (tester) async {
    // Otherwise "Careerjet has no key" and "there are no jobs for you" look
    // identical to a student, and only one of those is their problem.
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(
        const RadarResult(
          listings: [],
          problems: {'careerjet': 'not configured'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ONE BOARD IS OFF'), findsOneWidget);
    expect(bodyText(tester), contains('Careerjet covers Bangladesh'));
  });

  testWidgets('the two views swap without leaving the destination', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(RadarResult(listings: [listing()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend developer'), findsWidgets);

    await tester.tap(find.text('Tracking'));
    await tester.pumpAndSettle();

    expect(find.text('No applications yet'), findsOneWidget);
    // Still Radar: the tab bar did not move.
    expect(find.text('Radar'), findsWidgets);
  });

  testWidgets('it lays out at the 360px floor without overflow', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 640),
      overrides: overrides(
        RadarResult(
          listings: [
            listing(),
            listing(
              id: 'l2',
              title: 'Senior Software Engineer, Platform Infrastructure',
              remote: true,
              fit: 30,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the Radar tab label fits at 360px', (tester) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: overrides(const RadarResult(listings: [])),
    );
    await tester.pumpAndSettle();

    // Scoped to the bar: "Radar" is also the screen's own title, so an
    // unscoped finder matches twice.
    for (final tab in TackTabs.all) {
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(TackBottomNav),
                matching: find.text(tab.label),
              ),
            )
            .width,
        lessThanOrEqualTo(360 / 5),
        reason: '${tab.label} is too wide',
      );
    }
  });
}
