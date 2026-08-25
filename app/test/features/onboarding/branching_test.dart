import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/application/onboarding_controller.dart';
import 'package:tack/features/onboarding/data/onboarding_steps.dart';
import 'package:tack/features/onboarding/data/reference_repository.dart';
import 'package:tack/features/onboarding/presentation/direction_step.dart';
import 'package:tack/features/onboarding/presentation/interests_step.dart';
import 'package:tack/features/onboarding/presentation/stage_step.dart';
import 'package:tack/features/onboarding/presentation/study_step.dart';
import 'package:tack/features/profile/data/education_stage.dart';

import '../../helpers.dart';

List<Override> refs() => [
  countriesProvider.overrideWith(
    (ref) async => const [
      Country(id: 'bd', iso2: 'BD', name: 'Bangladesh', dialCode: '+880'),
    ],
  ),
  universitiesProvider.overrideWith(
    (ref) async => const [
      University(id: 'buet', name: 'BUET', shortName: 'BUET'),
    ],
  ),
  popularSkillsProvider.overrideWith(
    (ref) async => const [
      Skill(id: 's1', slug: 'python', name: 'Python', category: 'programming'),
    ],
  ),
];

/// The real screens sit inside TackScaffold, which brings a Material ancestor
/// with it. Text fields require one, so the harness has to supply it too.
Widget wrap(Widget child) => Scaffold(
  body: SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: child),
    ),
  ),
);

void main() {
  setUpAll(loadTackFonts);

  group('the stage step', () {
    testWidgets('offers all four stages, each explained', (tester) async {
      await pumpAt(
        tester,
        wrap(
          const StageStep(draft: OnboardingDraft(step: OnboardingStep.stage)),
        ),
        overrides: refs(),
      );

      for (final stage in EducationStage.values) {
        expect(find.text(stage.label), findsOneWidget);
        expect(
          find.text(stage.blurb),
          findsOneWidget,
          reason: '"high school" means different things in different systems',
        );
      }
    });

    testWidgets('choosing primary explains why, rather than failing silently', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const StageStep(
            draft: OnboardingDraft(
              step: OnboardingStep.stage,
              stage: EducationStage.primary,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(find.byType(NotYetForYou), findsOneWidget);
      expect(find.textContaining('not built for you yet'), findsOneWidget);
      expect(
        find.textContaining('Come back when you start high school'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a supported stage says what the app will do', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const StageStep(
            draft: OnboardingDraft(
              step: OnboardingStep.stage,
              stage: EducationStage.highSchool,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(find.byType(NotYetForYou), findsNothing);
      expect(
        find.textContaining('Nothing about jobs or applications yet'),
        findsOneWidget,
      );
    });
  });

  group('the study step asks a different question of each stage', () {
    testWidgets('a school student is asked for a class, never a degree', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const StudyStep(
            draft: OnboardingDraft(
              step: OnboardingStep.study,
              stage: EducationStage.highSchool,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(find.text('Your school or college'), findsOneWidget);
      expect(find.text('Which class'), findsOneWidget);
      expect(find.text('Degree'), findsNothing);
      expect(find.text('University'), findsNothing);
    });

    testWidgets("a bachelor's student is asked for a degree and a year", (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const StudyStep(
            draft: OnboardingDraft(
              step: OnboardingStep.study,
              stage: EducationStage.bachelors,
            ),
          ),
        ),
        overrides: refs(),
      );
      await tester.pump();

      expect(find.text('Degree'), findsOneWidget);
      expect(find.text('Which year are you in?'), findsOneWidget);
      expect(find.text('Which class'), findsNothing);
    });

    testWidgets('a graduate is asked when they finished, not which year', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const StudyStep(
            draft: OnboardingDraft(
              step: OnboardingStep.study,
              stage: EducationStage.graduated,
            ),
          ),
        ),
        overrides: refs(),
      );
      await tester.pump();

      expect(find.text('Graduated in'), findsOneWidget);
      expect(find.text('Which year are you in?'), findsNothing);
      expect(find.text('Where you studied'), findsOneWidget);
    });
  });

  group('interests', () {
    testWidgets('a school student names subjects and things they do', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const InterestsStep(
            draft: OnboardingDraft(
              step: OnboardingStep.interests,
              stage: EducationStage.highSchool,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(find.text('Subjects you like most'), findsOneWidget);
      expect(find.text('Things you do outside class'), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Search skills'), findsNothing);
    });

    testWidgets('an undergraduate gets the skill vocabulary instead', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const InterestsStep(
            draft: OnboardingDraft(
              step: OnboardingStep.interests,
              stage: EducationStage.bachelors,
            ),
          ),
        ),
        overrides: refs(),
      );
      await tester.pump();

      expect(find.text('Search skills'), findsOneWidget);
      expect(find.text('Subjects you like most'), findsNothing);
    });
  });

  group('direction', () {
    testWidgets('a school student is asked what to study, not which job', (
      tester,
    ) async {
      await pumpAt(
        tester,
        wrap(
          const DirectionStep(
            draft: OnboardingDraft(
              step: OnboardingStep.direction,
              stage: EducationStage.highSchool,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(
        find.text('What would you like to study after school?'),
        findsOneWidget,
      );
      expect(find.text('Computer science or software'), findsOneWidget);
      expect(
        find.text('Frontend developer'),
        findsNothing,
        reason: 'a job title is the wrong question two years early',
      );
    });

    testWidgets('an undergraduate is asked which job', (tester) async {
      await pumpAt(
        tester,
        wrap(
          const DirectionStep(
            draft: OnboardingDraft(
              step: OnboardingStep.direction,
              stage: EducationStage.bachelors,
            ),
          ),
        ),
        overrides: refs(),
      );

      expect(find.text('What kind of job are you aiming at?'), findsOneWidget);
      expect(find.text('Frontend developer'), findsOneWidget);
    });
  });

  group('every branch lays out at the 360px minimum', () {
    testWidgets('without overflowing', (tester) async {
      for (final stage in [
        EducationStage.highSchool,
        EducationStage.bachelors,
        EducationStage.graduated,
      ]) {
        for (final step in [
          OnboardingStep.study,
          OnboardingStep.interests,
          OnboardingStep.direction,
        ]) {
          final draft = OnboardingDraft(step: step, stage: stage);
          final widget = switch (step) {
            OnboardingStep.study => StudyStep(draft: draft),
            OnboardingStep.interests => InterestsStep(draft: draft),
            _ => DirectionStep(draft: draft),
          };

          await pumpAt(tester, wrap(widget), overrides: refs());
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${stage.name} / ${step.name} overflowed at 360px',
          );
        }
      }
    });
  });
}
