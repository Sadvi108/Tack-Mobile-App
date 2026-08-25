import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/education_stage.dart';
import '../application/onboarding_controller.dart';
import '../data/onboarding_steps.dart';
import 'basics_step.dart';
import 'direction_step.dart';
import 'interests_step.dart';
import 'stage_step.dart';
import 'study_step.dart';

/// The onboarding wizard.
///
/// Five steps, and which questions appear in three of them depends on the
/// answer to the second. Progress at the top, a back link, and Continue pinned
/// outside the scroll region. Every step saves as it is answered, so a dropped
/// connection costs at most the step in progress.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return async.when(
      loading: () => const _OnboardingLoading(),
      error: (error, _) => TackScaffold(
        header: const TackHeader(title: 'Getting set up'),
        body: TackErrorState(
          body:
              'Your details did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(onboardingControllerProvider),
        ),
      ),
      data: (draft) {
        final step = draft.step;
        final blocked =
            step == OnboardingStep.stage &&
            draft.stage == EducationStage.primary;

        return TackScaffold(
          header: TackHeader(
            title: step.titleFor(draft.stage),
            subtitle: step.blurbFor(draft.stage),
            onBack: draft.path.before(step) == null ? null : controller.back,
            progress: SegmentedProgress(
              total: draft.stepCount,
              current: draft.stepNumber,
            ),
          ),
          pinnedCta: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (draft.failure != null) ...[
                Text(
                  draft.failure!.message,
                  style: TackText.fieldError,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TackSpace.sm),
              ],
              // A primary student is offered a way out rather than a Continue
              // that cannot go anywhere.
              if (blocked)
                TackButton.secondary(
                  'Choose something else',
                  onPressed: () => controller.patch(
                    (d) => OnboardingDraft(
                      step: d.step,
                      fullName: d.fullName,
                      countryId: d.countryId,
                      dialCode: d.dialCode,
                      cityId: d.cityId,
                      phone: d.phone,
                    ),
                  ),
                )
              else
                TackButton(
                  step == OnboardingStep.direction ? 'Finish' : 'Continue',
                  loading: draft.busy,
                  onPressed: draft.canContinue
                      ? () async {
                          final done = await controller.saveAndContinue();
                          if (done && context.mounted) context.go(Routes.home);
                        }
                      : null,
                ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: TackSpace.sm),
              switch (step) {
                OnboardingStep.basics => BasicsStep(
                  key: const ValueKey('basics'),
                  draft: draft,
                ),
                OnboardingStep.stage => StageStep(
                  key: const ValueKey('stage'),
                  draft: draft,
                ),
                OnboardingStep.study => StudyStep(
                  // Rebuilt when the stage changes, because the form is a
                  // different form.
                  key: ValueKey('study-${draft.stage?.wire}'),
                  draft: draft,
                ),
                OnboardingStep.interests => InterestsStep(
                  key: ValueKey('interests-${draft.stage?.wire}'),
                  draft: draft,
                ),
                OnboardingStep.direction => DirectionStep(
                  key: ValueKey('direction-${draft.stage?.wire}'),
                  draft: draft,
                ),
              },
              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }
}

class _OnboardingLoading extends StatelessWidget {
  const _OnboardingLoading();

  @override
  Widget build(BuildContext context) {
    return const TackScaffold(
      header: TackHeader(title: 'Getting set up'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: TackSpace.lg),
          TackSkeleton(height: 52, radius: 12),
          SizedBox(height: TackSpace.stack),
          TackSkeleton(height: 52, radius: 12),
          SizedBox(height: TackSpace.stack),
          TackSkeleton(height: 52, radius: 12),
        ],
      ),
    );
  }
}
