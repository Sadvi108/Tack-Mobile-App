import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/onboarding/application/intake_controller.dart';
import 'package:tack/features/onboarding/data/option_repository.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';
import 'package:tack/features/onboarding/presentation/review_screen.dart';
import 'package:tack/features/onboarding/presentation/step_renderer.dart';

const _speaking = '58aa5e01-a38e-4751-aa13-aeaec5c634b4';
const _solving = 'fa0feb1f-bd85-4362-b36c-332624703b13';

/// Starts on whatever state the test hands it. Nothing reaches the network.
class _Intake extends IntakeController {
  _Intake(this.initial);

  final IntakeState initial;

  @override
  Future<IntakeState> build() async => initial;
}

class _Options extends OptionRepository {
  _Options()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<PickerOption<String>>> load(
    OptionSource source, {
    String? countryId,
  }) async => const [
    PickerOption(value: _speaking, label: 'Public speaking'),
    PickerOption(value: _solving, label: 'Problem solving'),
  ];
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  IntakeState state,
  Widget child,
) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        intakeControllerProvider.overrideWith(() => _Intake(state)),
        optionRepositoryProvider.overrideWithValue(_Options()),
      ],
      child: MaterialApp(
        theme: buildTackTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

void main() {
  // "Check it over" listed skills as database ids, and the stage and
  // activities as the words the database stores them under.
  testWidgets('the review shows names, not ids or stored words', (
    tester,
  ) async {
    final state = IntakeState(
      stepId: 'review',
      branch: OnboardingBranch.bachelors,
      answers: {
        'stage': 'bachelors',
        'skills': [_speaking, _solving],
        'skills__labels': {
          _speaking: 'Public speaking',
          _solving: 'Problem solving',
        },
        'activities': ['sports'],
        'activities__labels': {'sports': 'Sports'},
      },
    );
    await _pump(tester, state, ReviewBody(state: state));

    expect(find.text("Doing a bachelor's degree"), findsOneWidget);
    expect(find.text('Public speaking, Problem solving'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    expect(find.textContaining(_speaking), findsNothing);
    expect(find.text('bachelors'), findsNothing);
  });

  testWidgets('ticking a chip keeps its name beside its id', (tester) async {
    final state = IntakeState(
      stepId: OnboardingFlow.uniCourses.id,
      branch: OnboardingBranch.bachelors,
      answers: const {'stage': 'bachelors'},
    );
    final container = await _pump(tester, state, StepRenderer(state: state));

    // The renderer reads state from its parent; feed each change back in the
    // way the intake screen does.
    await tester.tap(find.text('Public speaking'));
    await tester.pump();

    final answers = container.read(intakeControllerProvider).value!.answers;
    expect(answers['skills'], [_speaking]);
    expect(answers['skills__labels'], {_speaking: 'Public speaking'});
  });
}
