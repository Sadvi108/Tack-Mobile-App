import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../application/intake_controller.dart';
import '../domain/flow_config.dart';

/// Everything the student said, grouped, with a way back to each step.
///
/// The last chance to fix something before it becomes real data, and the first
/// time they see the whole picture at once.
class ReviewBody extends ConsumerWidget {
  const ReviewBody({super.key, required this.state});

  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intakeControllerProvider.notifier);
    final steps = OnboardingFlow.stepsFor(
      state.branch,
    ).where((s) => s.id != 'review').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps) ...[
          _Section(
            step: step,
            state: state,
            onEdit: () => controller.goTo(step.id),
          ),
          const SizedBox(height: TackSpace.stack),
        ],
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
                  'You can change any of this later from your profile. Nothing '
                  'here is fixed.',
                  style: TackText.bodyMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.step,
    required this.state,
    required this.onEdit,
  });

  final StepSpec step;
  final IntakeState state;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final answered = step.fields
        .map((f) => (f, _describe(f)))
        .where((pair) => pair.$2 != null)
        .toList();

    return TackCard(
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(step.title, style: TackText.cardTitle)),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: TackSpace.tapTarget,
                    minWidth: TackSpace.tapTarget,
                  ),
                  child: Center(
                    child: Text(
                      'Edit',
                      style: TackText.pill.copyWith(
                        color: TackColors.maroon,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (answered.isEmpty)
            Text('Nothing added', style: TackText.bodyMuted)
          else
            for (final (field, value) in answered) ...[
              const TackDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field.label, style: TackText.monoLabelSmall),
                    const SizedBox(height: 3),
                    Text(value!, style: TackText.body),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  /// A readable version of one answer, or null when it was left blank.
  String? _describe(FieldSpec field) {
    final raw = state.answers[field.key];
    if (raw == null) return null;

    if (raw is List) {
      final custom =
          (state.answers['${field.key}__custom'] as List?) ?? const [];
      final all = [...raw, ...custom].map((e) => '$e').toList();
      return all.isEmpty ? null : all.join(', ');
    }

    final text = '$raw'.trim();
    if (text.isEmpty) return null;

    // Selects store an id; the label was kept alongside it for exactly this.
    return (state.answers['${field.key}__label'] as String?) ?? text;
  }
}
