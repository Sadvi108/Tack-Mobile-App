import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/core/supabase/client.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_repository.dart';
import 'package:tack/features/settings/presentation/settings_screen.dart';

import '../../helpers.dart';

User student() => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  email: 'nusrat@example.com',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

Profile profile() => Profile(
  id: 'u1',
  fullName: 'Nusrat Jahan',
  countryId: 'bd',
  countryName: 'Bangladesh',
  cityId: 'dhaka',
  cityName: 'Dhaka',
  phone: '1712345678',
  dialCode: '+880',
  stage: EducationStage.bachelors,
  yearOfStudy: 4,
  yearsTotal: 4,
  mode: YearMode.launch,
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

List<Override> overrides({int queued = 0, bool online = true}) => [
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(online)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(queued)),
  profileProvider.overrideWith((ref) async => profile()),
  currentUserProvider.overrideWithValue(student()),
];

void main() {
  setUpAll(loadTackFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the account the student is actually signed in as', (
    tester,
  ) async {
    await pumpAt(tester, const SettingsScreen(), overrides: overrides());
    await tester.pumpAndSettle();

    expect(find.text('nusrat@example.com'), findsOneWidget);
    expect(find.text('+880 1712345678'), findsOneWidget);
    expect(find.text('Nusrat Jahan'), findsOneWidget);
  });

  testWidgets('says nothing is waiting when nothing is', (tester) async {
    await pumpAt(tester, const SettingsScreen(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('Nothing'), findsOneWidget);
  });

  // A separate test rather than a second pumpAt in the one above: pumping a
  // new tree into the same tester reuses the mounted widget and the overrides
  // never take, so the assertion passes against the old state.
  testWidgets('counts queued changes in words, and says when it is offline', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const SettingsScreen(),
      overrides: overrides(queued: 1, online: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 change'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('the theme row reports the choice that is in force', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'tack.appearance': 'dark'});
    await pumpAt(tester, const SettingsScreen(), overrides: overrides());
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('fits the 360px floor with nothing overflowing', (tester) async {
    await pumpAt(tester, const SettingsScreen(), overrides: overrides());
    await tester.pumpAndSettle();

    expect(hasOverflow(tester), isFalse);
    expect(tester.getSize(find.byType(SettingsScreen)).width, 360);
  });

  testWidgets('the whole screen scrolls, so nothing is stranded off-screen', (
    tester,
  ) async {
    await pumpAt(tester, const SettingsScreen(), overrides: overrides());
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Log out'),
      200,
      scrollable: list,
    );
    expect(find.text('Log out'), findsOneWidget);
  });
}
