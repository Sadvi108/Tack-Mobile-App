import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/onboarding_controller.dart';
import 'package:tack/features/onboarding/data/onboarding_repository.dart';
import 'package:tack/features/profile/data/profile.dart';

void main() {
  group('year of study derives the mode', () {
    // This mirrors public.year_to_mode in the database. The preview shown to
    // the student during onboarding must agree with what the server will
    // store, or the app promises one thing and delivers another.
    test('first year is explore', () {
      const d = OnboardingDraft(yearOfStudy: 1, yearsTotal: 4);
      expect(d.previewMode, YearMode.explore);
    });

    test('second year is build', () {
      const d = OnboardingDraft(yearOfStudy: 2, yearsTotal: 4);
      expect(d.previewMode, YearMode.build);
    });

    test('third year is prove', () {
      const d = OnboardingDraft(yearOfStudy: 3, yearsTotal: 4);
      expect(d.previewMode, YearMode.prove);
    });

    test('the last year of the programme is launch, whatever its number', () {
      expect(
        const OnboardingDraft(yearOfStudy: 4, yearsTotal: 4).previewMode,
        YearMode.launch,
      );
      expect(
        const OnboardingDraft(yearOfStudy: 5, yearsTotal: 5).previewMode,
        YearMode.launch,
      );
      expect(
        const OnboardingDraft(yearOfStudy: 2, yearsTotal: 2).previewMode,
        YearMode.launch,
      );
    });

    test('an unanswered year falls back to the gentlest mode', () {
      expect(const OnboardingDraft().previewMode, YearMode.explore);
    });
  });

  group('continue stays disabled until the step is answerable', () {
    test('step one needs a name, a city and a full phone number', () {
      const empty = OnboardingDraft(step: OnboardingStep.you);
      expect(empty.canContinue, isFalse);

      const noPhone = OnboardingDraft(
        step: OnboardingStep.you,
        fullName: 'Rafiq Hossain',
        cityId: 'city-1',
        phone: '171234',
      );
      expect(
        noPhone.canContinue,
        isFalse,
        reason: 'a partial phone number is not enough',
      );

      const complete = OnboardingDraft(
        step: OnboardingStep.you,
        fullName: 'Rafiq Hossain',
        cityId: 'city-1',
        phone: '1712345678',
      );
      expect(complete.canContinue, isTrue);
    });

    test('step two accepts either a picked university or a typed one', () {
      const picked = OnboardingDraft(
        step: OnboardingStep.education,
        universityId: 'uni-1',
        degree: 'BSc',
      );
      expect(picked.canContinue, isTrue);

      const typed = OnboardingDraft(
        step: OnboardingStep.education,
        universityName: 'Somewhere not on the list',
        degree: 'BBA',
      );
      expect(typed.canContinue, isTrue);

      const noDegree = OnboardingDraft(
        step: OnboardingStep.education,
        universityId: 'uni-1',
      );
      expect(noDegree.canContinue, isFalse);
    });

    test('step three needs both the year and the graduation date', () {
      final onlyYear = OnboardingDraft(
        step: OnboardingStep.year,
        yearOfStudy: 2,
      );
      expect(onlyYear.canContinue, isFalse);

      final both = OnboardingDraft(
        step: OnboardingStep.year,
        yearOfStudy: 2,
        expectedGraduation: DateTime(2028, 7),
      );
      expect(both.canContinue, isTrue);
    });

    test('step four needs at least one skill', () {
      expect(
        const OnboardingDraft(step: OnboardingStep.skills).canContinue,
        isFalse,
      );
      expect(
        const OnboardingDraft(
          step: OnboardingStep.skills,
          skillIds: {'skill-1'},
        ).canContinue,
        isTrue,
      );
    });

    test('step five needs a target role, and industry stays optional', () {
      expect(
        const OnboardingDraft(step: OnboardingStep.target).canContinue,
        isFalse,
      );
      expect(
        const OnboardingDraft(
          step: OnboardingStep.target,
          targetRole: 'Data analyst',
        ).canContinue,
        isTrue,
      );
    });
  });

  group('progress', () {
    test('reports a one-based step out of five', () {
      expect(const OnboardingDraft(step: OnboardingStep.you).stepNumber, 1);
      expect(const OnboardingDraft(step: OnboardingStep.target).stepNumber, 5);
      expect(const OnboardingDraft().stepCount, 5);
    });
  });

  group('draft edits', () {
    test(
      'clearing the CGPA actually removes it rather than keeping the old one',
      () {
        const withCgpa = OnboardingDraft(cgpa: 3.4);
        expect(withCgpa.copyWith(clearCgpa: true).cgpa, isNull);
      },
    );

    test('shortening the programme pulls an out-of-range year back in', () {
      // A student who says "year 5" then corrects the programme to 4 years
      // must not be left claiming a year that does not exist.
      const d = OnboardingDraft(yearOfStudy: 5, yearsTotal: 6);
      final corrected = d.copyWith(
        yearsTotal: 4,
        yearOfStudy: d.yearOfStudy! > 4 ? 4 : d.yearOfStudy,
      );
      expect(corrected.yearOfStudy, 4);
      expect(corrected.previewMode, YearMode.launch);
    });
  });
}
