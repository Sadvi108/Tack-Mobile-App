import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/application/interview.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';

import 'helpers.dart';
import 'shot_util.dart';

CompanyPack pack(String slug, String name, int n) => CompanyPack(
  slug: slug,
  name: name,
  about: 'About $name',
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
        companyPacksProvider.overrideWith(
          (ref) async => [
            pack('bkash', 'bKash', 4),
            pack('grameenphone', 'Grameenphone', 4),
            pack('pathao', 'Pathao', 4),
            pack('brac', 'BRAC', 4),
          ],
        ),
        interviewCatalogProvider.overrideWith(
          (ref) async => const InterviewCatalog(
            suggested: RoleSuggestion(
              slug: 'backend-developer',
              title: 'Backend developer',
              fieldSlug: 'computer-science',
              fieldName: 'Computer science and software',
              reason: RoleReason.yourTarget,
            ),
            fields: [
              InterviewField(
                slug: 'computer-science',
                name: 'Computer science and software',
                roles: [
                  InterviewRole(
                    slug: 'backend-developer',
                    title: 'Backend developer',
                    questionCount: 15,
                  ),
                ],
              ),
            ],
          ),
        ),
        dueQuestionsProvider.overrideWith((ref) async => const []),
      ],
      panels: const [0, 700],
    );
  });
}
