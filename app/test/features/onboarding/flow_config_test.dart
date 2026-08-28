import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';
import 'package:tack/features/profile/data/education_stage.dart';

void main() {
  group('the flow is data', () {
    test('each branch has its own length, and the bar reflects it', () {
      // Branches are genuinely different lengths; a fixed count would lie to
      // whichever student is not on the longest one.
      expect(OnboardingFlow.lengthOf(OnboardingBranch.highSchool), 6);
      expect(OnboardingFlow.lengthOf(OnboardingBranch.bachelors), 6);
      expect(OnboardingFlow.lengthOf(OnboardingBranch.graduated), 5);
    });

    test('before a branch is chosen the bar assumes the longest one', () {
      // Otherwise a student is half way along the bar on question one, and it
      // then jumps backwards when they pick — which reads as the goalposts
      // moving rather than as progress.
      expect(OnboardingFlow.lengthOf(null), 6);
      expect(OnboardingFlow.stepsFor(null), hasLength(2));
    });

    test('everyone starts with the same two steps', () {
      for (final branch in OnboardingBranch.values) {
        final steps = OnboardingFlow.stepsFor(branch);
        expect(steps.first.id, 'basics');
        expect(steps[1].id, 'stage');
      }
    });

    test('primary goes no further than the fork', () {
      // It ends at the waitlist and creates no account, so it has no steps of
      // its own to walk.
      final steps = OnboardingFlow.stepsFor(OnboardingBranch.primary);
      expect(steps.map((s) => s.id), ['basics', 'stage']);
      expect(OnboardingFlow.next('stage', OnboardingBranch.primary), isNull);
    });

    test('every accepted branch ends at review', () {
      for (final branch in [
        OnboardingBranch.highSchool,
        OnboardingBranch.bachelors,
        OnboardingBranch.graduated,
      ]) {
        expect(OnboardingFlow.stepsFor(branch).last.id, 'review');
      }
    });

    test('a branch only ever contains its own steps', () {
      for (final branch in [
        OnboardingBranch.highSchool,
        OnboardingBranch.bachelors,
        OnboardingBranch.graduated,
      ]) {
        for (final step in OnboardingFlow.stepsFor(branch)) {
          expect(
            step.branch,
            anyOf(isNull, branch),
            reason: '${step.id} does not belong on ${branch.name}',
          );
        }
      }
    });
  });

  group('walking the flow', () {
    test('next and previous are inverses', () {
      for (final branch in OnboardingBranch.values) {
        final steps = OnboardingFlow.stepsFor(branch);
        for (var i = 0; i < steps.length - 1; i++) {
          final forward = OnboardingFlow.next(steps[i].id, branch);
          expect(forward?.id, steps[i + 1].id);
          expect(OnboardingFlow.previous(forward!.id, branch)?.id, steps[i].id);
        }
      }
    });

    test('the first step has nothing before it', () {
      expect(
        OnboardingFlow.previous('basics', OnboardingBranch.bachelors),
        isNull,
      );
    });

    test('position is one-based and within the branch', () {
      expect(
        OnboardingFlow.positionOf('basics', OnboardingBranch.bachelors),
        1,
      );
      expect(
        OnboardingFlow.positionOf('review', OnboardingBranch.graduated),
        5,
      );
    });
  });

  group('the questions themselves', () {
    test(
      'a school student is asked about subjects, never about a CGPA scale',
      () {
        final keys = OnboardingFlow.highSchoolSteps
            .expand((s) => s.fields.map((f) => f.key))
            .toSet();
        expect(keys, contains('favourite_subjects'));
        expect(keys, contains('hard_subjects'));
        expect(keys, isNot(contains('year_of_study')));
        expect(keys, isNot(contains('target_role')));
      },
    );

    test('an undergraduate is asked the year, and it is flagged as the one '
        'that matters', () {
      final year = OnboardingFlow.uniUniversity.fields.firstWhere(
        (f) => f.key == 'year_of_study',
      );
      expect(year.required, isTrue);
      expect(year.help, contains('decides everything'));
    });

    test(
      'a graduate is asked when they finished, not which year they are in',
      () {
        final keys = OnboardingFlow.graduatedSteps
            .expand((s) => s.fields.map((f) => f.key))
            .toSet();
        expect(keys, contains('graduation'));
        expect(keys, contains('current_status'));
        expect(keys, isNot(contains('year_of_study')));
      },
    );

    test('"not sure yet" is offered wherever direction is asked', () {
      // Not knowing is the honest state for most people, and the flow rewards
      // it rather than leaving it as a blank.
      final directionFields = [
        ...OnboardingFlow.highSchoolSteps,
        ...OnboardingFlow.bachelorsSteps,
        ...OnboardingFlow.graduatedSteps,
      ].expand((s) => s.fields).where((f) => f.isDirectionQuestion);

      expect(directionFields, isNotEmpty);
      for (final field in directionFields) {
        expect(field.notSureOption, 'Not sure yet');
      }

      for (final key in ['intended_field_slug', 'target_role']) {
        final matches = [
          ...OnboardingFlow.highSchoolSteps,
          ...OnboardingFlow.bachelorsSteps,
          ...OnboardingFlow.graduatedSteps,
        ].expand((s) => s.fields).where((f) => f.key == key);
        expect(matches, isNotEmpty, reason: '$key should exist');
        for (final field in matches) {
          expect(
            field.isDirectionQuestion,
            isTrue,
            reason: '$key must offer it',
          );
        }
      }
    });

    test('fields that depend on country say so, so they can be cleared', () {
      final dependent = [
        OnboardingFlow.basics,
        ...OnboardingFlow.highSchoolSteps,
        ...OnboardingFlow.bachelorsSteps,
        ...OnboardingFlow.graduatedSteps,
      ].expand((s) => s.fields).where((f) => f.dependsOn == 'country_id');

      expect(dependent.map((f) => f.key), contains('city_id'));
      expect(dependent.map((f) => f.key), contains('phone'));
      expect(dependent.map((f) => f.key), contains('institution_id'));
    });

    test('where an answer is private, the field says so', () {
      final gpaFields = [
        ...OnboardingFlow.highSchoolSteps,
        ...OnboardingFlow.bachelorsSteps,
        ...OnboardingFlow.graduatedSteps,
      ].expand((s) => s.fields).where((f) => f.key == 'gpa');

      expect(gpaFields, isNotEmpty);
      for (final field in gpaFields) {
        expect(field.help, contains('never shown'));
      }
    });

    test('the ten-year note is capped where the column is', () {
      final note = OnboardingFlow.hsDirection.fields.firstWhere(
        (f) => f.key == 'ten_year_note',
      );
      expect(note.maxLength, 200);
    });
  });

  test('a stage maps to exactly one branch', () {
    expect(
      OnboardingBranch.forStage(EducationStage.highSchool),
      OnboardingBranch.highSchool,
    );
    expect(
      OnboardingBranch.forStage(EducationStage.graduated),
      OnboardingBranch.graduated,
    );
    expect(OnboardingBranch.forStage(null), isNull);
  });
}
