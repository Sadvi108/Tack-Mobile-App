import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/intake_controller.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';

IntakeState stateWith(Map<String, dynamic> answers, {String step = 'basics'}) =>
    IntakeState(
      stepId: step,
      answers: answers,
      branch: OnboardingBranch.forStage(
        EducationStage.fromWire(answers['stage'] as String?),
      ),
    );

void main() {
  group('the under-13 guard', () {
    test('an under-13 age band stops the flow', () {
      expect(stateWith({'age_band': 'under_13'}).tooYoung, isTrue);
    });

    test('every other band does not', () {
      for (final band in ['13_15', '16_18', '19_22', '23_26', '27_plus']) {
        expect(stateWith({'age_band': band}).tooYoung, isFalse, reason: band);
      }
    });

    test('a birth year is honoured when no band was given', () {
      expect(
        stateWith({'birth_year': DateTime.now().year - 11}).tooYoung,
        isTrue,
      );
      expect(
        stateWith({'birth_year': DateTime.now().year - 20}).tooYoung,
        isFalse,
      );
    });

    test('no age answer at all is not a block', () {
      // Nothing said yet is not the same as saying they are twelve.
      expect(stateWith({}).tooYoung, isFalse);
    });
  });

  group('continue is driven by the config, not by the screen', () {
    test('basics needs a name, country, city and age', () {
      expect(stateWith({}).canContinue, isFalse);
      expect(
        stateWith({
          'full_name': 'Nusrat',
          'country_id': 'bd',
          'city_id': 'dhaka',
        }).canContinue,
        isFalse,
        reason: 'the age question is required',
      );
      expect(
        stateWith({
          'full_name': 'Nusrat',
          'country_id': 'bd',
          'city_id': 'dhaka',
          'age_band': '16_18',
        }).canContinue,
        isTrue,
      );
    });

    test('the phone number is optional', () {
      final state = stateWith({
        'full_name': 'Nusrat',
        'country_id': 'bd',
        'city_id': 'dhaka',
        'age_band': '16_18',
      });
      expect(state.answers.containsKey('phone'), isFalse);
      expect(state.canContinue, isTrue);
    });

    test('a chip field with a minimum needs that many', () {
      final none = stateWith({'stage': 'high_school'}, step: 'hs_enjoy');
      expect(none.canContinue, isFalse);

      final one = stateWith({
        'stage': 'high_school',
        'favourite_subjects': ['physics'],
      }, step: 'hs_enjoy');
      expect(one.canContinue, isTrue);
    });

    test('review needs nothing more, because everything was asked already', () {
      expect(
        stateWith({'stage': 'graduated'}, step: 'review').canContinue,
        isTrue,
      );
    });
  });

  group('the mode preview follows the answers', () {
    test('a school student previews discover', () {
      expect(
        stateWith({'stage': 'high_school'}).previewMode,
        YearMode.discover,
      );
    });

    test('a final-year undergraduate previews launch', () {
      expect(
        stateWith({
          'stage': 'bachelors',
          'year_of_study': 4,
          'years_total': 4,
        }).previewMode,
        YearMode.launch,
      );
    });

    test('year 4 of 5 previews prove, not launch', () {
      expect(
        stateWith({
          'stage': 'bachelors',
          'year_of_study': 4,
          'years_total': 5,
        }).previewMode,
        YearMode.prove,
      );
    });

    test('answers stored as strings are read the same as integers', () {
      // A picker may hand back either; the preview must not care.
      expect(
        stateWith({
          'stage': 'bachelors',
          'year_of_study': '4',
          'years_total': '4',
        }).previewMode,
        YearMode.launch,
      );
    });
  });

  group('branch selection', () {
    test('the stage answer decides the branch and its length', () {
      expect(stateWith({'stage': 'high_school'}).length, 6);
      expect(stateWith({'stage': 'graduated'}).length, 5);
    });

    test('primary is a branch that goes nowhere', () {
      final state = stateWith({'stage': 'primary'}, step: 'stage');
      expect(state.branch, OnboardingBranch.primary);
      expect(OnboardingFlow.next('stage', state.branch), isNull);
    });

    test('position is within the branch, not a global count', () {
      expect(stateWith({'stage': 'graduated'}, step: 'review').position, 5);
      expect(stateWith({'stage': 'high_school'}, step: 'review').position, 6);
    });
  });
}
