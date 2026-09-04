import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/data/interview_models.dart';
import 'package:tack/features/interview/data/interview_repository.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile_repository.dart';

import 'helpers.dart';
import 'shot_util.dart';

CompanyPack pack(String slug, String name, int n) => CompanyPack(
  slug: slug, name: name, about: 'About $name',
  questions: List.generate(n, (i) => 'Question ${i + 1}'),
);

void main() {
  setUpAll(loadTackFonts);

  testWidgets('interview setup with company packs', (tester) async {
    await shoot(
      tester,
      const InterviewScreen(),
      'interview-setup',
      const Size(390, 844),
      overrides: [
        interviewHistoryProvider.overrideWith((ref) async => const []),
        companyPacksProvider.overrideWith((ref) async => [
          pack('bkash', 'bKash', 4),
          pack('grameenphone', 'Grameenphone', 4),
          pack('pathao', 'Pathao', 4),
          pack('brac', 'BRAC', 4),
        ]),
        profileProvider.overrideWith((ref) async => Profile(
          id: 'u1', fullName: 'Rafiq Hossain',
          countryId: 'bd', countryName: 'Bangladesh',
          cityId: 'dhaka', cityName: 'Dhaka',
          stage: EducationStage.bachelors, mode: YearMode.launch,
          targetRole: 'Backend developer',
          onboardingCompletedAt: DateTime(2026, 1, 1),
        )),
      ],
      panels: const [0, 700],
    );
  });
}
