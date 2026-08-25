import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../application/onboarding_controller.dart';
import '../data/reference_repository.dart';

/// What you enjoy.
///
/// A school student names favourite subjects and things they do outside class;
/// an undergraduate names courses and skills. Both are the same question —
/// what are you drawn to — and both feed the same score component, so a
/// sixteen-year-old is not stuck at zero for two years waiting to have skills.
class InterestsStep extends ConsumerStatefulWidget {
  const InterestsStep({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<InterestsStep> createState() => _InterestsStepState();
}

class _InterestsStepState extends ConsumerState<InterestsStep> {
  final _search = TextEditingController();
  String _query = '';

  static const _schoolSubjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'ICT',
    'English',
    'Bangla',
    'Economics',
    'Accounting',
    'Business studies',
    'Geography',
    'History',
    'Civics',
    'Islamic studies',
    'Statistics',
    'Higher mathematics',
    'Agriculture',
    'Psychology',
    'Art',
    'Physical education',
  ];

  static const _hobbies = [
    'Reading',
    'Writing',
    'Drawing',
    'Photography',
    'Music',
    'Debating',
    'Programming',
    'Gaming',
    'Football',
    'Cricket',
    'Volunteering',
    'Robotics',
    'Science olympiad',
    'Cooking',
    'Gardening',
    'Editing videos',
    'Public speaking',
    'Chess',
    'Travelling',
    'Teaching others',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(onboardingControllerProvider.notifier);

    if (draft.isAtSchool) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Group(
            title: 'Subjects you like most',
            hint: 'Pick as many as you want',
            options: _schoolSubjects,
            selected: draft.favourites,
            onToggle: (label) {
              final next = {...draft.favourites};
              next.contains(label) ? next.remove(label) : next.add(label);
              controller.patch((d) => d.copyWith(favourites: next));
            },
            onAdd: (label) => controller.patch(
              (d) => d.copyWith(favourites: {...d.favourites, label}),
            ),
          ),
          const SizedBox(height: TackSpace.xl),
          _Group(
            title: 'Things you do outside class',
            hint: 'Clubs, sports, anything you spend time on',
            options: _hobbies,
            selected: draft.hobbies,
            onToggle: (label) {
              final next = {...draft.hobbies};
              next.contains(label) ? next.remove(label) : next.add(label);
              controller.patch((d) => d.copyWith(hobbies: next));
            },
            onAdd: (label) => controller.patch(
              (d) => d.copyWith(hobbies: {...d.hobbies, label}),
            ),
          ),
        ],
      );
    }

    // University and graduate: the skill vocabulary, searchable.
    final searching = _query.trim().length >= 2;
    final results = searching
        ? ref.watch(skillSearchProvider(_query))
        : ref.watch(popularSkillsProvider);
    final count = draft.skillIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackSearchField(
          hint: 'Search skills',
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: TackSpace.md),
        Text(
          count == 0
              ? 'Nothing picked yet'
              : '$count ${count == 1 ? 'skill' : 'skills'} picked',
          style: TackText.monoLabel,
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
            ],
          ),
          error: (_, _) => Text(
            'Skills did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (skills) => Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final skill in skills)
                TackChip(
                  skill.name,
                  selected: draft.skillIds.contains(skill.id),
                  onTap: () {
                    final next = {...draft.skillIds};
                    next.contains(skill.id)
                        ? next.remove(skill.id)
                        : next.add(skill.id);
                    controller.patch((d) => d.copyWith(skillIds: next));
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: TackSpace.xl),
        _Group(
          title: 'Courses you enjoyed most',
          hint: 'Optional, and it helps the roadmap',
          options: const [],
          selected: draft.favourites,
          onToggle: (label) {
            final next = {...draft.favourites}..remove(label);
            controller.patch((d) => d.copyWith(favourites: next));
          },
          onAdd: (label) => controller.patch(
            (d) => d.copyWith(favourites: {...d.favourites, label}),
          ),
        ),
      ],
    );
  }
}

/// A chip grid with an escape hatch, used for both branches.
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.hint,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onAdd,
  });

  final String title;
  final String hint;
  final List<String> options;
  final Set<String> selected;
  final void Function(String label) onToggle;
  final void Function(String label) onAdd;

  @override
  Widget build(BuildContext context) {
    // Anything the student typed themselves, shown alongside the presets.
    final extras = selected.where((s) => !options.contains(s)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TackText.fieldLabel),
        const SizedBox(height: 2),
        Text(hint, style: TackText.meta.copyWith(fontSize: 13.5)),
        const SizedBox(height: TackSpace.md),
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (final option in [...options, ...extras])
              TackChip(
                option,
                selected: selected.contains(option),
                onTap: () => onToggle(option),
              ),
          ],
        ),
        const SizedBox(height: TackSpace.md),
        TackButton.ghost(
          '+ Add your own',
          fullWidth: false,
          onPressed: () => _addOwn(context),
        ),
      ],
    );
  }

  Future<void> _addOwn(BuildContext context) async {
    final controller = TextEditingController();
    final entered = await showTackSheet<String>(
      context: context,
      title: title,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TackTextField(
              hint: 'Type it as you would say it',
              controller: controller,
              autofocus: true,
            ),
            const SizedBox(height: TackSpace.lg),
            Builder(
              builder: (sheetContext) => TackButton(
                'Add it',
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
    final text = entered?.trim();
    controller.dispose();
    if (text != null && text.isNotEmpty) onAdd(text);
  }
}
