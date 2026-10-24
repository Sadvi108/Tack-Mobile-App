import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/features/radar/application/radar_data.dart';
import 'package:tack/features/radar/presentation/radar_screen.dart';

import '../../helpers.dart';
import 'radar_screen_test.dart' as fixture;

class _Repository extends RadarRepository {
  _Repository()
    : super(
        SupabaseClient(
          'https://example.test',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final calls = <({RadarQuery query, int offset, bool refresh})>[];
  bool failPage = false;
  int saves = 0;

  @override
  Future<RadarResult> search(
    RadarQuery query, {
    int offset = 0,
    bool refresh = true,
  }) async {
    calls.add((query: query, offset: offset, refresh: refresh));
    if (failPage) {
      failPage = false;
      throw Exception('offline');
    }
    return RadarResult(
      listings: [fixture.listing(id: 'page-2', title: 'Accounts trainee')],
    );
  }

  @override
  Future<String> save(String listingId) async {
    saves++;
    return 'saved-application';
  }
}

void main() {
  setUpAll(loadTackFonts);

  testWidgets('workplace and job type combine without clearing the city', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: fixture.overrides(const RadarResult(listings: [])),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarScreen)),
    );
    expect(container.read(radarQueryProvider).workplace, RadarWorkplace.all);
    await tester.ensureVisible(find.text('In person'));
    await tester.tap(find.text('In person'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Internships'));
    await tester.tap(find.text('Internships'));
    await tester.pumpAndSettle();
    expect(container.read(radarQueryProvider).filter, RadarFilter.internship);
    expect(container.read(radarQueryProvider).workplace.remoteValue, false);
    expect(container.read(radarQueryProvider).location, 'Dhaka');
    await tester.ensureVisible(find.text('Remote'));
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    expect(container.read(radarQueryProvider).filter, RadarFilter.internship);
    expect(container.read(radarQueryProvider).workplace.remoteValue, true);
  });

  testWidgets('a chosen city is visible and reaches the query at 360px', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      overrides: fixture.overrides(const RadarResult(listings: [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location: Dhaka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sylhet'));
    await tester.pumpAndSettle();
    expect(find.text('Location: Sylhet'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarScreen)),
    );
    expect(container.read(radarQueryProvider).location, 'Sylhet');
    expect(tester.takeException(), isNull);
  });

  testWidgets('location entry stays usable above the keyboard', (tester) async {
    await pumpAt(
      tester,
      const RadarScreen(),
      overrides: fixture.overrides(const RadarResult(listings: [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location: Dhaka'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).last, 'Gazipur');
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();
    expect(find.text('Location: Gazipur'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paging retries the same offset and does not refresh paid sources',
    (tester) async {
      final repository = _Repository()..failPage = true;
      await pumpAt(
        tester,
        const RadarScreen(),
        size: const Size(360, 900),
        overrides: [
          ...fixture.overrides(
            RadarResult(
              listings: List.generate(20, (i) => fixture.listing(id: 'l$i')),
            ),
          ),
          radarRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Load more openings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more openings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try loading more again'));
      await tester.pumpAndSettle();
      expect(repository.calls.map((c) => c.offset), [20, 20]);
      expect(repository.calls.every((c) => !c.refresh), isTrue);
      expect(find.text('Accounts trainee'), findsOneWidget);
      expect(find.text('Load more openings'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved feedback survives changing filters', (tester) async {
    final repository = _Repository();
    await pumpAt(
      tester,
      const RadarScreen(),
      size: const Size(360, 900),
      overrides: [
        ...fixture.overrides(RadarResult(listings: [fixture.listing()])),
        radarRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save it'));
    await tester.tap(find.text('Save it'));
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(find.text('In your tracker'), findsOneWidget);
    await tester.ensureVisible(find.text('Internships'));
    await tester.tap(find.text('Internships'));
    await tester.pumpAndSettle();
    expect(find.text('In your tracker'), findsOneWidget);
    expect(find.text('Save it'), findsNothing);
  });
}
