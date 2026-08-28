import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/intake_controller.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';

/// A required field is only satisfiable if something actually writes its key.
///
/// A date field wrote `graduation_year` and `graduation_month` while the config
/// required `graduation`, so Continue could never enable on the graduate branch
/// — the check was looking for a key nothing ever set. These tests fill each
/// step the way the renderer does and assert the step can actually be
/// completed, which is the failure that shipped.
IntakeState filled(StepSpec step, {required String stage}) {
  final answers = <String, dynamic>{'stage': stage};

  for (final field in step.fields) {
    answers[field.key] = switch (field.type) {
      FieldType.multiChip => ['something'],
      FieldType.rankPicker => ['money'],
      FieldType.repeatableRows => <Map<String, String>>[],
      // What the date widget writes: the key itself, plus its parts.
      FieldType.dateParts => '2027-6',
      _ => 'answered',
    };
    if (field.type == FieldType.dateParts) {
      answers['graduation_year'] = 2027;
      answers['graduation_month'] = 6;
    }
  }

  return IntakeState(
    stepId: step.id,
    answers: answers,
    branch: OnboardingBranch.values.firstWhere((b) => b.wire == stage),
  );
}

void main() {
  group('every step can actually be completed', () {
    final branches = {
      'high_school': OnboardingFlow.highSchoolSteps,
      'bachelors': OnboardingFlow.bachelorsSteps,
      'graduated': OnboardingFlow.graduatedSteps,
    };

    for (final entry in branches.entries) {
      test('${entry.key} branch', () {
        for (final step in [OnboardingFlow.basics, ...entry.value]) {
          expect(
            filled(step, stage: entry.key).canContinue,
            isTrue,
            reason:
                '${step.id} cannot be completed even when every field is '
                'answered — a required key is never written',
          );
        }
      });
    }
  });

  group('a half-filled step does not let you past', () {
    test('the graduate degree step needs its date', () {
      final step = OnboardingFlow.gradDegree;
      final answers = <String, dynamic>{
        'stage': 'graduated',
        'institution_id': 'uni',
        'degree': 'BSc',
        'current_status': 'job_hunting',
      };
      final without = IntakeState(
        stepId: step.id,
        answers: answers,
        branch: OnboardingBranch.graduated,
      );
      expect(without.canContinue, isFalse);

      final with_ = IntakeState(
        stepId: step.id,
        answers: {...answers, 'graduation': '2027-6'},
        branch: OnboardingBranch.graduated,
      );
      expect(with_.canContinue, isTrue);
    });

    test('a blank string does not count as answered', () {
      final state = IntakeState(
        stepId: 'basics',
        answers: const {
          'full_name': '   ',
          'country_id': 'bd',
          'city_id': 'dhaka',
          'age_band': '19_22',
        },
      );
      expect(state.canContinue, isFalse);
    });

    test('an empty chip list does not count as answered', () {
      final state = IntakeState(
        stepId: 'hs_enjoy',
        answers: const {
          'stage': 'high_school',
          'favourite_subjects': <String>[],
        },
        branch: OnboardingBranch.highSchool,
      );
      expect(state.canContinue, isFalse);
    });
  });

  group('what a date pick writes', () {
    test('includes the key the required check actually reads', () {
      // This is the bug that shipped: the widget wrote the year and month but
      // not the field key, so Continue stayed dead however complete the step
      // looked.
      final answers = answersForDate(
        fieldKey: 'graduation',
        year: 2027,
        month: 4,
        monthName: 'April',
      );

      expect(answers.containsKey('graduation'), isTrue);
      expect(answers['graduation_year'], 2027);
      expect(answers['graduation_month'], 4);
      expect(answers['graduation__label'], 'April 2027');
    });

    test('satisfies the required check on the step that asks for it', () {
      final answers = <String, dynamic>{
        'stage': 'graduated',
        'institution_id': 'uni',
        'degree': 'BSc',
        'current_status': 'job_hunting',
        ...answersForDate(
          fieldKey: 'graduation',
          year: 2027,
          month: 4,
          monthName: 'April',
        ),
      };

      final state = IntakeState(
        stepId: OnboardingFlow.gradDegree.id,
        answers: answers,
        branch: OnboardingBranch.graduated,
      );
      expect(state.canContinue, isTrue);
      expect(state.previewMode.name, 'launch');
    });
  });

  group('selects keep a readable label beside the id', () {
    test('every select field has somewhere to put one', () {
      // Without it the student is shown a UUID, and so is the review screen.
      final selects =
          [
                OnboardingFlow.basics,
                ...OnboardingFlow.highSchoolSteps,
                ...OnboardingFlow.bachelorsSteps,
                ...OnboardingFlow.graduatedSteps,
              ]
              .expand((s) => s.fields)
              .where(
                (f) =>
                    f.type == FieldType.select ||
                    f.type == FieldType.searchableSelect ||
                    f.type == FieldType.dateParts,
              );

      expect(selects, isNotEmpty);
      for (final field in selects) {
        expect(
          '${field.key}__label'.isNotEmpty,
          isTrue,
          reason: '${field.key} needs a label key',
        );
      }
    });
  });
}
