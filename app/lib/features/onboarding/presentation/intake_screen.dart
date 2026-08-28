import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../design/tack.dart';
import '../../profile/data/education_stage.dart';
import '../application/intake_controller.dart';
import '../domain/flow_config.dart';
import 'review_screen.dart';
import 'score_reveal_screen.dart';
import 'step_renderer.dart';
import 'waitlist_screen.dart';

/// The onboarding shell.
///
/// Progress at the top, a back link, and the Continue button pinned outside
/// the scroll region — that last part is load-bearing, it is what keeps the
/// primary action reachable with a thumb when the keyboard is open.
///
/// The screen knows nothing about which questions it is showing. It reads the
/// config, renders the step, and asks the controller what comes next.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  String? _tracked;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(intakeControllerProvider);
    final controller = ref.read(intakeControllerProvider.notifier);

    return async.when(
      loading: () => const _IntakeLoading(),
      error: (_, _) => TackScaffold(
        header: const TackHeader(title: 'Getting set up'),
        body: TackErrorState(
          body:
              'Your answers did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(intakeControllerProvider),
        ),
      ),
      data: (state) {
        // The score reveal replaces the flow once it is finished.
        if (state.finishedScore != null) {
          return ScoreRevealScreen(
            score: state.finishedScore!,
            mode: state.previewMode,
          );
        }

        // Two exits that create no profile at all.
        if (state.stepId == 'basics' && state.tooYoung) {
          return const WaitlistScreen(reason: WaitlistReason.tooYoung);
        }
        if (state.stepId == 'stage' && state.stage == EducationStage.primary) {
          return const WaitlistScreen(reason: WaitlistReason.tooEarly);
        }

        // One event per step, the first time it is seen. This is the only way
        // the drop-off point ever becomes visible.
        if (_tracked != state.stepId) {
          _tracked = state.stepId;
          ref
              .read(analyticsProvider)
              .track(
                'onboarding_step_viewed',
                properties: {
                  'step': state.stepId,
                  if (state.branch != null) 'branch': state.branch!.wire,
                },
              )
              .ignore();
        }

        final isReview = state.stepId == 'review';
        final canGoBack =
            OnboardingFlow.previous(state.stepId, state.branch) != null;

        return TackScaffold(
          header: TackHeader(
            title: state.step.title,
            subtitle: state.step.subtitle,
            onBack: canGoBack ? controller.back : null,
            progress: SegmentedProgress(
              total: state.length,
              current: state.position,
            ),
          ),
          pinnedCta: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.failure != null) ...[
                // A failed save keeps everything typed; the student retries
                // rather than starting the step again.
                Text(
                  state.failure!.message,
                  style: TackText.fieldError,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TackSpace.sm),
              ],
              TackButton(
                isReview ? 'Finish setup' : 'Continue',
                loading: state.busy,
                onPressed: state.canContinue
                    ? () => controller.saveAndContinue()
                    : null,
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: TackSpace.sm),
              if (isReview)
                ReviewBody(state: state)
              else
                StepRenderer(key: ValueKey(state.stepId), state: state),
              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }
}

class _IntakeLoading extends StatelessWidget {
  const _IntakeLoading();

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
