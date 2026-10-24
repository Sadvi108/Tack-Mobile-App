import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/intake_controller.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';

FieldSpec _gpa(StepSpec step) => step.fields.firstWhere((f) => f.key == 'gpa');

IntakeState _university(Object? gpa) => IntakeState(
  stepId: OnboardingFlow.uniUniversity.id,
  branch: OnboardingBranch.bachelors,
  answers: {
    'stage': 'bachelors',
    'institution_id': 'du',
    'degree': 'BSc',
    'year_of_study': '3',
    'years_total': '4',
    'graduation': '2028-6',
    'gpa': ?gpa,
  },
);

void main() {
  // A CGPA of 9.9 went through onboarding and was stored against a scale of
  // 4: nothing on the screen or in the database said it could not be right.
  group('a university CGPA is out of 4', () {
    test('above 4 stops Continue and says why', () {
      final state = _university('9.9');
      expect(state.canContinue, isFalse);
      expect(
        state.errorFor(_gpa(OnboardingFlow.uniUniversity)),
        'This is out of 4. Enter 4 or less.',
      );
    });

    test('3.45 is fine', () {
      final state = _university('3.45');
      expect(state.canContinue, isTrue);
      expect(state.errorFor(_gpa(OnboardingFlow.uniUniversity)), isNull);
    });

    test('4 exactly is fine', () {
      expect(_university('4').canContinue, isTrue);
    });

    test('left blank is fine, because it is optional', () {
      expect(_university(null).canContinue, isTrue);
      expect(_university('').canContinue, isTrue);
    });

    test('something that is not a number asks for one', () {
      final state = _university('3..4');
      expect(state.canContinue, isFalse);
      expect(
        state.errorFor(_gpa(OnboardingFlow.uniUniversity)),
        'Enter a number, like 3.45.',
      );
    });
  });

  test('a graduate CGPA is out of 4 too', () {
    expect(_gpa(OnboardingFlow.gradDegree).max, 4);
  });

  // SSC and HSC results are out of 5, and the field's own example is 4.83.
  test('a school result is out of 5', () {
    final field = _gpa(OnboardingFlow.hsSchool);
    expect(field.max, 5);

    final state = IntakeState(
      stepId: OnboardingFlow.hsSchool.id,
      branch: OnboardingBranch.highSchool,
      answers: const {'gpa': '4.83'},
    );
    expect(state.errorFor(field), isNull);
  });
}
