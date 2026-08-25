import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/data/education_stage.dart';
import '../application/onboarding_controller.dart';

/// The fork the whole app turns on.
///
/// Four options, each with a line saying what it means, because "high school"
/// and "college" mean different things in different systems and a student
/// should not have to guess which one Tack means.
class StageStep extends ConsumerWidget {
  const StageStep({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stage in EducationStage.values) ...[
          _StageOption(
            stage: stage,
            selected: draft.stage == stage,
            onTap: () => controller.patch((d) => d.copyWith(stage: stage)),
          ),
          const SizedBox(height: TackSpace.row),
        ],

        // Shown as soon as primary is picked, rather than after a Continue tap
        // that goes nowhere.
        if (draft.stage == EducationStage.primary) ...[
          const SizedBox(height: TackSpace.sm),
          const NotYetForYou(),
        ] else if (draft.stage != null) ...[
          const SizedBox(height: TackSpace.sm),
          TackCard(
            background: TackColors.maroonPale,
            compact: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TackIcon(
                  TackIcons.info,
                  size: 20,
                  color: TackColors.maroon,
                ),
                const SizedBox(width: TackSpace.md),
                Expanded(
                  child: Text(
                    _explain(draft.stage!),
                    style: TackText.bodyMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _explain(EducationStage stage) => switch (stage) {
    EducationStage.primary => '',
    EducationStage.highSchool =>
      'Tack will help you work out what to study and what you are good at. '
          'Nothing about jobs or applications yet.',
    EducationStage.bachelors =>
      'Tack will change as you move through your degree, from exploring in '
          'first year to applying in your last.',
    EducationStage.graduated =>
      'Tack will focus on applications, your CV and interview practice.',
  };
}

class _StageOption extends StatelessWidget {
  const _StageOption({
    required this.stage,
    required this.selected,
    required this.onTap,
  });

  final EducationStage stage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: stage.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: TackSpace.cardCompactX,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.listCardAll,
            border: Border.all(
              color: selected ? TackColors.maroon : TackColors.line2,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _Radio(selected: selected),
              const SizedBox(width: TackSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.label,
                      style: TackText.rowTitle.copyWith(
                        color: selected ? TackColors.maroon : TackColors.ink,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(stage.blurb, style: TackText.meta),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TackMotion.fast,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? TackColors.maroon : TackColors.line2,
          width: selected ? 6.5 : 1.5,
        ),
      ),
    );
  }
}

/// What a primary student sees.
///
/// The honest answer is that Tack has nothing for them yet, and saying so
/// plainly respects their time more than letting them fill in five screens
/// that lead to an empty dashboard. It is written as "not yet" rather than
/// "no", because it is true and because they will be back in a few years.
class NotYetForYou extends StatelessWidget {
  const NotYetForYou({super.key});

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: TackColors.amberTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TackIcon(
                TackIcons.info,
                size: 22,
                color: TackColors.amberText,
              ),
              const SizedBox(width: TackSpace.sm),
              Expanded(
                child: Text(
                  'Tack is not built for you yet',
                  style: TackText.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          Text(
            'Everything in Tack is about choosing a subject, building skills and '
            'finding a first job. That is still a few years away for you, and we '
            'would rather say so than have you fill in forms for a plan you cannot '
            'use yet.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.md),
          Text(
            'Come back when you start high school. Keep reading, keep trying things, '
            'and that will already be a head start.',
            style: TackText.bodyMuted,
          ),
        ],
      ),
    );
  }
}
