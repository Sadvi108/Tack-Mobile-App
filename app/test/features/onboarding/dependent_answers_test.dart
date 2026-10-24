import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/intake_controller.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';

/// Starts on the answers the test hands it. Nothing reaches the network.
class _Intake extends IntakeController {
  _Intake(this.initial);

  final IntakeState initial;

  @override
  Future<IntakeState> build() async => initial;
}

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: [
      intakeControllerProvider.overrideWith(
        () => _Intake(
          const IntakeState(
            stepId: 'basics',
            branch: OnboardingBranch.bachelors,
            answers: {
              'stage': 'bachelors',
              'country_id': 'bd',
              'city_id': 'dhaka',
              'institution_id': 'du',
            },
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(intakeControllerProvider.future);
  return container;
}

void main() {
  // Opening the country picker and tapping the country already chosen wiped
  // the city and the university. The student only found out a step later,
  // when Continue would not light up.
  test(
    'picking the same country again keeps the city and university',
    () async {
      final container = await _container();
      container
          .read(intakeControllerProvider.notifier)
          .answer('country_id', 'bd');

      final answers = container.read(intakeControllerProvider).value!.answers;
      expect(answers['city_id'], 'dhaka');
      expect(answers['institution_id'], 'du');
    },
  );

  test(
    'a different country still clears what belonged to the old one',
    () async {
      final container = await _container();
      container
          .read(intakeControllerProvider.notifier)
          .answer('country_id', 'in');

      final answers = container.read(intakeControllerProvider).value!.answers;
      expect(answers['country_id'], 'in');
      expect(answers.containsKey('city_id'), isFalse);
      expect(answers.containsKey('institution_id'), isFalse);
    },
  );
}
