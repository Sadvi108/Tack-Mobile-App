import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/features/profile/application/completeness.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_repository.dart';
import 'package:tack/features/profile/data/profile_sections.dart';
import 'package:tack/features/profile/data/profile_sections_repository.dart';
import 'package:tack/features/profile/presentation/profile_screen.dart';

import '../../helpers.dart';

Profile schoolStudent() => Profile(
  id: 'u2',
  fullName: 'Nusrat Jahan',
  countryId: 'bd',
  countryName: 'Bangladesh',
  cityId: 'dhaka',
  cityName: 'Dhaka',
  phone: '+8801712345678',
  stage: EducationStage.highSchool,
  mode: YearMode.discover,
  intendedField: 'Computer science',
  passion: 'Building small games',
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

Profile undergraduate() => Profile(
  id: 'u1',
  fullName: 'Rafiq Hossain',
  countryId: 'bd',
  countryName: 'Bangladesh',
  cityId: 'dhaka',
  cityName: 'Dhaka',
  stage: EducationStage.bachelors,
  yearOfStudy: 4,
  yearsTotal: 4,
  mode: YearMode.launch,
  targetRole: 'Frontend developer',
  targetIndustry: const ['Software and IT'],
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

List<Override> overridesFor(
  Profile profile,
  Map<ProfileSection, List<ProfileEntry>> sections,
) => [
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  profileProvider.overrideWith((ref) async => profile),
  profileSectionsProvider.overrideWith((ref) async => sections),
  userSkillsProvider.overrideWith((ref) async => const <UserSkill>[]),
  completenessProvider.overrideWith(
    (ref) async => computeCompleteness(
      profile: profile,
      sections: sections,
      skillCount: 0,
    ),
  ),
];

String allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  setUpAll(loadTackFonts);

  testWidgets('the personal card shows country and stage, not just a city', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 900),
      overrides: overridesFor(undergraduate(), const {}),
    );
    await tester.pump();

    final text = allText(tester);
    expect(text, contains('Dhaka, Bangladesh'));
    expect(text, contains('Final year · launch'));
    expect(text, contains("Doing a bachelor's degree"));
  });

  testWidgets('an undergraduate sees the job they are aiming at', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 900),
      overrides: overridesFor(undergraduate(), const {}),
    );
    await tester.pump();

    final text = allText(tester);
    expect(text, contains('What you are aiming at'));
    expect(text, contains('Frontend developer'));
    expect(text, contains('Software and IT'));
    expect(text, isNot(contains('What you want to study')));
  });

  testWidgets('a school student sees what they want to study and enjoy', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 900),
      overrides: overridesFor(schoolStudent(), const {}),
    );
    await tester.pump();

    final text = allText(tester);
    expect(text, contains('What you want to study'));
    expect(text, contains('Computer science'));
    expect(text, contains('Building small games'));
    expect(text, contains('At school · explore'));
    expect(text, isNot(contains('What you are aiming at')));
  });

  testWidgets('a school student gets subjects and hobbies, not courses', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 1400),
      overrides: overridesFor(schoolStudent(), {
        ProfileSection.favourites: [
          const ProfileEntry(id: '1', title: 'Physics'),
        ],
        ProfileSection.hobbies: [const ProfileEntry(id: '2', title: 'Chess')],
      }),
    );
    await tester.pump();

    final text = allText(tester);
    expect(text, contains('Favourite subjects'));
    expect(text, contains('Physics'));
    expect(text, contains('Outside class'));
    expect(text, contains('Chess'));
    expect(text, isNot(contains('Courses')));
    expect(text, isNot(contains('Experience')));
  });

  testWidgets('the completeness banner names what is missing', (tester) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 900),
      overrides: overridesFor(schoolStudent(), const {}),
    );
    await tester.pump();

    final text = allText(tester);
    expect(text, contains('Profile'));
    expect(text, contains('complete'));
    // The banner is a to-do, so it names an action rather than only a number.
    expect(text, anyOf(contains('things left'), contains('One thing left')));
  });

  testWidgets('the profile lays out at 360px without overflowing', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 640),
      overrides: overridesFor(undergraduate(), const {}),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding an entry does not outlive its own text fields', (
    tester,
  ) async {
    // The sheet used to be built by the screen, which disposed the controllers
    // the moment showTackSheet returned — that is when pop is called, not when
    // the sheet is gone. The fields stayed mounted through the closing
    // animation and the next frame rebuilt them against disposed controllers,
    // which killed the screen with a red assertion. pumpAndSettle runs that
    // whole animation, so this fails if the ordering regresses.
    final saved = <(ProfileSection, Map<String, Object?>)>[];
    final profile = undergraduate();

    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 800),
      overrides: [
        ...overridesFor(profile, const {}),
        sectionInsertProvider.overrideWithValue((section, values) async {
          saved.add((section, values));
        }),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Update education'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Uttara University');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(saved, hasLength(1));
    expect(saved.first.$1, ProfileSection.education);
    expect(saved.first.$2['institution_name'], 'Uttara University');
  });

  testWidgets('closing the sheet without saving writes nothing', (
    tester,
  ) async {
    final saved = <(ProfileSection, Map<String, Object?>)>[];

    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 800),
      overrides: [
        ...overridesFor(undergraduate(), const {}),
        sectionInsertProvider.overrideWithValue((section, values) async {
          saved.add((section, values));
        }),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Update education'));
    await tester.pumpAndSettle();

    // Nothing typed, so Save has nothing to save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(saved, isEmpty);
  });

  testWidgets('the education section reads what onboarding wrote', (
    tester,
  ) async {
    // The columns here are education_profiles', not the old education table's.
    // Reading the wrong one is what told a student who had answered every
    // question during signup to "add where you study".
    await pumpAt(
      tester,
      const ProfileScreen(),
      size: const Size(360, 800),
      overrides: overridesFor(undergraduate(), const {
        ProfileSection.education: [
          ProfileEntry(
            id: 'e1',
            title: 'Uttara University',
            subtitle: 'University',
            meta: 'Finishing 2026',
          ),
        ],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uttara University'), findsOneWidget);
    expect(find.text('Add where you study'), findsNothing);
  });
}
