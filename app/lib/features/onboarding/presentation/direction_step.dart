import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../application/onboarding_controller.dart';

/// Where you want to end up.
///
/// A school student is asked what they want to study; everyone else is asked
/// what job they want. Asking a sixteen-year-old to pick a job title would be
/// asking the wrong question two years early.
class DirectionStep extends ConsumerStatefulWidget {
  const DirectionStep({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<DirectionStep> createState() => _DirectionStepState();
}

class _DirectionStepState extends ConsumerState<DirectionStep> {
  late final _passion = TextEditingController(text: widget.draft.passion);

  static const _fields = [
    'Computer science or software',
    'Engineering',
    'Business or management',
    'Economics or finance',
    'Accounting',
    'Medicine or health',
    'Law',
    'Design or architecture',
    'Media or communication',
    'Social sciences',
    'Natural sciences',
    'Teaching',
    'Still deciding',
  ];

  static const _roles = [
    'Frontend developer',
    'Backend developer',
    'Data analyst',
    'Digital marketer',
    'HR executive',
    'Business analyst',
    'Graphic designer',
    'QA engineer',
    'Accountant',
    'Content writer',
    'Still deciding',
  ];

  static const _industries = [
    'Software and IT',
    'Banking and finance',
    'Telecom',
    'E-commerce',
    'RMG and textiles',
    'FMCG',
    'Pharmaceuticals',
    'Education',
    'Development and NGO',
    'Media and advertising',
    'Startups',
    'Government',
  ];

  @override
  void dispose() {
    _passion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final atSchool = draft.isAtSchool;

    final options = atSchool ? _fields : _roles;
    final selected = atSchool ? draft.intendedField : draft.targetRole;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          atSchool
              ? 'What would you like to study after school?'
              : 'What kind of job are you aiming at?',
          style: TackText.fieldLabel,
        ),
        const SizedBox(height: TackSpace.sm),
        TackCard(
          padding: const EdgeInsets.symmetric(
            horizontal: TackSpace.cardX,
            vertical: 4,
          ),
          child: Column(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const TackDivider(),
                TackTapRow(
                  onTap: () => controller.patch(
                    (d) => atSchool
                        ? d.copyWith(intendedField: options[i])
                        : d.copyWith(targetRole: options[i]),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      _Radio(selected: selected == options[i]),
                      const SizedBox(width: TackSpace.md),
                      Expanded(
                        child: Text(options[i], style: TackText.rowTitle),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TackSpace.xl),

        if (atSchool) ...[
          Text('What do you most enjoy doing?', style: TackText.fieldLabel),
          const SizedBox(height: 2),
          Text(
            'Optional, and there is no wrong answer. It helps Tack suggest '
            'things worth trying.',
            style: TackText.meta.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: TackSpace.md),
          TackTextField(
            hint:
                'Building small games, arguing about politics, fixing things…',
            controller: _passion,
            maxLines: 3,
            onChanged: (v) => controller.patch((d) => d.copyWith(passion: v)),
          ),
        ] else ...[
          Text(
            'Any industries you like the look of?',
            style: TackText.fieldLabel,
          ),
          const SizedBox(height: 2),
          Text(
            'Optional. Pick as many as you want.',
            style: TackText.meta.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: TackSpace.md),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final industry in _industries)
                TackChip(
                  industry,
                  selected: draft.targetIndustry.contains(industry),
                  onTap: () {
                    final next = {...draft.targetIndustry};
                    next.contains(industry)
                        ? next.remove(industry)
                        : next.add(industry);
                    controller.patch((d) => d.copyWith(targetIndustry: next));
                  },
                ),
            ],
          ),
        ],
      ],
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
