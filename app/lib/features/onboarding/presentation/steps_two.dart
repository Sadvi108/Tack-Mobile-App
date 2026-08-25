import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../application/onboarding_controller.dart';
import '../data/reference_repository.dart';

/// Step 4 — skills. A search field over the full vocabulary plus a starter
/// grid, because a student who does not know what to type still needs a way in.
class StepSkills extends ConsumerStatefulWidget {
  const StepSkills({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<StepSkills> createState() => _StepSkillsState();
}

class _StepSkillsState extends ConsumerState<StepSkills> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final searching = _query.trim().length >= 2;
    final results = searching ? ref.watch(skillSearchProvider(_query)) : ref.watch(popularSkillsProvider);
    final count = draft.skillIds.length;

    void toggle(String id) {
      final next = {...draft.skillIds};
      next.contains(id) ? next.remove(id) : next.add(id);
      controller.patch((d) => d.copyWith(skillIds: next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackSearchField(
          hint: 'Search skills',
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: TackSpace.md),
        Row(
          children: [
            Text(
              count == 0
                  ? 'Nothing picked yet'
                  : '$count ${count == 1 ? 'skill' : 'skills'} picked',
              style: TackText.monoLabel,
            ),
            const Spacer(),
            if (!searching)
              Text('Tap any that apply', style: TackText.meta.copyWith(fontSize: 13)),
          ],
        ),
        const SizedBox(height: TackSpace.md),
        results.when(
          loading: () => const Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              TackSkeleton(width: 110, height: 44, radius: 22),
              TackSkeleton(width: 92, height: 44, radius: 22),
              TackSkeleton(width: 130, height: 44, radius: 22),
              TackSkeleton(width: 104, height: 44, radius: 22),
            ],
          ),
          error: (_, _) => Text(
            'Skills did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (skills) {
            if (skills.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing matches "${_query.trim()}".',
                    style: TackText.bodyMuted,
                  ),
                  const SizedBox(height: TackSpace.md),
                  TackButton.secondary(
                    '+ Add "${_query.trim()}" as a skill',
                    onPressed: () => _addUnlisted(context, _query.trim()),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: TackSpace.sm,
                  runSpacing: TackSpace.sm,
                  children: [
                    for (final skill in skills)
                      TackChip(
                        skill.name,
                        selected: draft.skillIds.contains(skill.id),
                        onTap: () => toggle(skill.id),
                      ),
                  ],
                ),
                const SizedBox(height: TackSpace.lg),
                TackButton.ghost(
                  '+ Add a skill not listed',
                  fullWidth: false,
                  onPressed: () => _addUnlisted(context, _search.text.trim()),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The escape hatch. The vocabulary is large but not complete, and a student
  /// whose skill is missing should not be told it does not count.
  Future<void> _addUnlisted(BuildContext context, String seed) async {
    final controller = TextEditingController(text: seed);
    final entered = await showTackSheet<String>(
      context: context,
      title: 'Add a skill',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TackSpace.screen, 0, TackSpace.screen, TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type the skill as you would write it on a CV. We will match it to the closest '
              'one we know.',
              style: TackText.bodyMuted,
            ),
            const SizedBox(height: TackSpace.lg),
            TackTextField(hint: 'For example, Bangla copywriting', controller: controller, autofocus: true),
            const SizedBox(height: TackSpace.lg),
            Builder(
              builder: (sheetContext) => TackButton(
                'Add it',
                onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    final text = entered?.trim();
    if (text == null || text.isEmpty || !mounted) return;

    final matches = await ref.read(referenceRepositoryProvider).searchSkills(text);
    if (!mounted) return;

    if (matches.isEmpty) {
      TackToast.show(
        this.context,
        message: 'We could not match "$text" yet. Pick the nearest one for now.',
        kind: TackToastKind.info,
      );
      return;
    }

    final match = matches.first;
    final next = {...widget.draft.skillIds, match.id};
    ref.read(onboardingControllerProvider.notifier).patch((d) => d.copyWith(skillIds: next));
    TackToast.show(this.context, message: 'Added ${match.name}.');
  }
}

/// Step 5 — target role and industry. A rough idea is enough; the roadmap is
/// generated from it and can be changed later.
class StepTarget extends ConsumerWidget {
  const StepTarget({super.key, required this.draft});

  final OnboardingDraft draft;

  static const roles = <String>[
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

  static const industries = <String>[
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
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What kind of job are you aiming at?', style: TackText.fieldLabel),
        const SizedBox(height: TackSpace.sm),
        TackCard(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.cardX, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < roles.length; i++) ...[
                if (i > 0) const TackDivider(),
                TackTapRow(
                  onTap: () => controller.patch((d) => d.copyWith(targetRole: roles[i])),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      _Radio(selected: draft.targetRole == roles[i]),
                      const SizedBox(width: TackSpace.md),
                      Expanded(child: Text(roles[i], style: TackText.rowTitle)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TackSpace.xl),
        Text('Any industries you like the look of?', style: TackText.fieldLabel),
        const SizedBox(height: TackSpace.xs),
        Text('Optional. Pick as many as you want.', style: TackText.meta.copyWith(fontSize: 13.5)),
        const SizedBox(height: TackSpace.md),
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (final industry in industries)
              TackChip(
                industry,
                selected: draft.targetIndustry.contains(industry),
                onTap: () {
                  final next = {...draft.targetIndustry};
                  next.contains(industry) ? next.remove(industry) : next.add(industry);
                  controller.patch((d) => d.copyWith(targetIndustry: next));
                },
              ),
          ],
        ),
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
