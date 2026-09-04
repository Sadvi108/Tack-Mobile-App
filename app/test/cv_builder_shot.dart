import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/cv_builder/data/profile_document.dart';
import 'package:tack/features/cv_builder/presentation/cv_builder_screen.dart';

import 'helpers.dart';
import 'shot_util.dart';

ProfileDocument _full() => ProfileDocument(
  identity: const Identity(fullName: 'Rafiq Hossain', headline: 'Backend developer'),
  education: const [Education(institution: 'BUET', degree: 'BSc')],
  experiences: [
    Experience(company: 'Pathao', title: 'Backend intern', startDate: DateTime(2025, 6)),
    Experience(company: 'BRAC IT', title: 'Junior developer', startDate: DateTime(2024, 7)),
  ],
  projects: const [Project(title: 'Bus tracker')],
  skills: const [Skill(name: 'Python'), Skill(name: 'PostgreSQL'), Skill(name: 'Git')],
  certifications: const [],
  activities: const [],
);

List<Override> _for(ProfileDocument doc) => [
  profileDocumentProvider.overrideWith((ref) async => doc),
  cvLayoutProvider.overrideWith((ref) async => const CvLayout()),
];

void main() {
  setUpAll(loadTackFonts);

  testWidgets('the builder', (tester) async {
    await shoot(tester, const CvBuilderScreen(), 'cv-builder',
        const Size(390, 844), overrides: _for(_full()));
  });

  testWidgets('nothing to build with', (tester) async {
    await shoot(
      tester,
      const CvBuilderScreen(),
      'cv-builder-empty',
      const Size(390, 844),
      overrides: _for(const ProfileDocument(identity: Identity(fullName: 'New Student'))),
    );
  });
}
