import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/onboarding_controller.dart';
import '../data/onboarding_repository.dart';
import 'steps.dart';
import 'steps_two.dart';

/// The onboarding wizard.
///
/// Five steps, each asking for one kind of thing so it clears in under 30
/// seconds. Progress at the top, a back link, and Continue pinned outside the
/// scroll region. Every step saves as it is answered, so a dropped connection
/// costs at most the step in progress.
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

        return TackScaffold(
          header: TackHeader(
            title: step.title,
            subtitle: step.blurb,
            onBack: step.index == 0 ? null : controller.back,
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
              TackButton(
                step == OnboardingStep.target ? 'Finish' : 'Continue',
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
                OnboardingStep.you => StepYou(
                  key: const ValueKey('you'),
                  draft: draft,
                ),
                OnboardingStep.education => StepEducation(
                  key: const ValueKey('education'),
                  draft: draft,
                ),
                OnboardingStep.year => StepYear(
                  key: const ValueKey('year'),
                  draft: draft,
                ),
                OnboardingStep.skills => StepSkills(
                  key: const ValueKey('skills'),
                  draft: draft,
                ),
                OnboardingStep.target => StepTarget(
                  key: const ValueKey('target'),
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
    return TackScaffold(
      header: const TackHeader(title: 'Getting set up'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
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
