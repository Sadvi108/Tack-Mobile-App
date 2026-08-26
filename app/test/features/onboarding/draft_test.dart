import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/onboarding_controller.dart';
import 'package:tack/features/onboarding/data/onboarding_steps.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';

void main() {
  group('the stage decides the mode', () {
    // This mirrors public.stage_to_mode. The preview shown while a student is
    // choosing must agree with what the server will store, or the app promises
    // one thing and delivers another.
    test('a school student is in school mode, whatever else they answer', () {
      const d = OnboardingDraft(
        stage: EducationStage.highSchool,
        yearOfStudy: 3,
      );
      expect(d.previewMode, YearMode.discover);
    });

    test('a graduate is in graduate mode', () {
      expect(
        const OnboardingDraft(stage: EducationStage.graduated).previewMode,
        YearMode.graduate,
      );
    });

    test('a bachelor\'s student still moves with their year', () {
      const total = 4;
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 1,
          yearsTotal: total,
        ).previewMode,
        YearMode.explore,
      );
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 2,
          yearsTotal: total,
        ).previewMode,
        YearMode.build,
      );
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 3,
          yearsTotal: total,
        ).previewMode,
        YearMode.prove,
      );
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 4,
          yearsTotal: total,
        ).previewMode,
        YearMode.launch,
      );
    });

    test('the last year of any length programme is launch', () {
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 2,
          yearsTotal: 2,
        ).previewMode,
        YearMode.launch,
      );
      expect(
        const OnboardingDraft(
          stage: EducationStage.bachelors,
          yearOfStudy: 5,
          yearsTotal: 5,
        ).previewMode,
        YearMode.launch,
      );
    });
  });

  group('primary students', () {
    test('are not supported, and every other stage is', () {
      expect(EducationStage.primary.isSupported, isFalse);
      for (final stage in [
        EducationStage.highSchool,
        EducationStage.bachelors,
        EducationStage.graduated,
      ]) {
        expect(
          stage.isSupported,
          isTrue,
          reason: '${stage.name} should go forward',
        );
      }
    });

    test('can still pick the option — the screen explains, not the button', () {
      // Disabling the option would leave them unable to say what is true.
      const d = OnboardingDraft(
        step: OnboardingStep.stage,
        stage: EducationStage.primary,
      );
      expect(d.canContinue, isTrue);
    });
  });

  group('continue stays disabled until the step is answerable', () {
    const basics = OnboardingStep.basics;

    test('basics needs a name, a country and a city', () {
      expect(const OnboardingDraft(step: basics).canContinue, isFalse);
      expect(
        const OnboardingDraft(
          step: basics,
          fullName: 'Nusrat',
          countryId: 'bd',
        ).canContinue,
        isFalse,
        reason: 'a country without a city is not enough',
      );
      expect(
        const OnboardingDraft(
          step: basics,
          fullName: 'Nusrat',
          countryId: 'bd',
          cityId: 'dhaka',
        ).canContinue,
        isTrue,
      );
    });

    test('the phone number is optional', () {
      // Requiring it turns away anyone who does not want to give it yet.
      const d = OnboardingDraft(
        step: basics,
        fullName: 'Nusrat',
        countryId: 'bd',
        cityId: 'dhaka',
      );
      expect(d.phone, isEmpty);
      expect(d.canContinue, isTrue);
    });

    test('a school student needs a school and a class, not a degree', () {
      const withoutClass = OnboardingDraft(
        step: OnboardingStep.study,
        stage: EducationStage.highSchool,
        institutionName: 'Dhaka College',
      );
      expect(withoutClass.canContinue, isFalse);

      const complete = OnboardingDraft(
        step: OnboardingStep.study,
        stage: EducationStage.highSchool,
        institutionName: 'Dhaka College',
        classLevel: 'Class 11 (HSC first year)',
      );
      expect(complete.canContinue, isTrue);
      expect(
        complete.degree,
        isEmpty,
        reason: 'a school student has no degree',
      );
    });

    test(
      "a bachelor's student needs a year, a graduate needs a year finished",
      () {
        const undergrad = OnboardingDraft(
          step: OnboardingStep.study,
          stage: EducationStage.bachelors,
          universityId: 'buet',
          degree: 'BSc',
        );
        expect(undergrad.canContinue, isFalse, reason: 'no year of study yet');
        expect(undergrad.copyWith(yearOfStudy: 2).canContinue, isTrue);

        const graduate = OnboardingDraft(
          step: OnboardingStep.study,
          stage: EducationStage.graduated,
          universityId: 'buet',
          degree: 'BSc',
        );
        expect(graduate.canContinue, isFalse, reason: 'no graduation year yet');
        expect(graduate.copyWith(graduationYear: 2025).canContinue, isTrue);
      },
    );

    test('interests accept a subject, a hobby or a skill', () {
      const step = OnboardingStep.interests;
      expect(const OnboardingDraft(step: step).canContinue, isFalse);
      expect(
        const OnboardingDraft(step: step, favourites: {'Physics'}).canContinue,
        isTrue,
      );
      expect(
        const OnboardingDraft(step: step, hobbies: {'Chess'}).canContinue,
        isTrue,
      );
      expect(
        const OnboardingDraft(step: step, skillIds: {'s1'}).canContinue,
        isTrue,
      );
    });

    test('a school student is asked what to study, not which job', () {
      const school = OnboardingDraft(
        step: OnboardingStep.direction,
        stage: EducationStage.highSchool,
      );
      expect(school.canContinue, isFalse);
      expect(school.copyWith(intendedField: 'Engineering').canContinue, isTrue);
      expect(
        school.copyWith(targetRole: 'Backend developer').canContinue,
        isFalse,
        reason: 'a job title is the wrong question two years early',
      );

      const undergrad = OnboardingDraft(
        step: OnboardingStep.direction,
        stage: EducationStage.bachelors,
      );
      expect(
        undergrad.copyWith(targetRole: 'Backend developer').canContinue,
        isTrue,
      );
    });
  });

  group('progress', () {
    test('reports a one-based step out of five for every stage', () {
      for (final stage in EducationStage.values) {
        final d = OnboardingDraft(step: OnboardingStep.basics, stage: stage);
        expect(d.stepNumber, 1);
        expect(d.stepCount, 5);
      }
    });

    test('the last step is the last step', () {
      const d = OnboardingDraft(step: OnboardingStep.direction);
      expect(d.stepNumber, d.stepCount);
      expect(d.path.after(OnboardingStep.direction), isNull);
      expect(d.path.before(OnboardingStep.basics), isNull);
    });
  });

  group('copying a draft', () {
    test('shortening a programme pulls an out-of-range year back in', () {
      const d = OnboardingDraft(
        stage: EducationStage.bachelors,
        yearOfStudy: 5,
        yearsTotal: 6,
      );
      final corrected = d.copyWith(
        yearsTotal: 4,
        yearOfStudy: d.yearOfStudy! > 4 ? 4 : d.yearOfStudy,
      );
      expect(corrected.yearOfStudy, 4);
      expect(corrected.previewMode, YearMode.launch);
    });

    test('clearing a CGPA actually removes it', () {
      expect(
        const OnboardingDraft(cgpa: 3.4).copyWith(clearCgpa: true).cgpa,
        isNull,
      );
    });

    test('choosing "other" clears the picked university', () {
      const d = OnboardingDraft(universityId: 'buet');
      expect(d.copyWith(clearUniversity: true).universityId, isNull);
    });
  });

  group('step titles change with the stage', () {
    test('the study step is a school or a degree, never both', () {
      expect(
        OnboardingStep.study.titleFor(EducationStage.highSchool),
        'Your school',
      );
      expect(
        OnboardingStep.study.titleFor(EducationStage.bachelors),
        'Your degree',
      );
    });

    test('a graduate is not asked about a CGPA they are still earning', () {
      expect(
        OnboardingStep.study.blurbFor(EducationStage.graduated),
        'What you finished, and where.',
      );
    });
  });
}
