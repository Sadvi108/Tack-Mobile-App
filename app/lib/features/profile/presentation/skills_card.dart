import 'package:flutter/material.dart';

import 'package:tack/design/tack.dart';
import '../application/profile_sections.dart';

/// A compact overview; proficiency is named once per group, not per skill.
class SkillsCard extends StatelessWidget {
  const SkillsCard({super.key, required this.skills});

  final List<UserSkill> skills;
  static const _previewCount = 8;

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered(skills);
    final preview = ordered.take(_previewCount).toList();
    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: TackSpace.tapTarget,
                height: TackSpace.tapTarget,
                decoration: BoxDecoration(
                  color: TackColors.tealTint,
                  borderRadius: TackRadius.inputAll,
                ),
                child: Center(
                  child: TackIcon(
                    TackIcons.roadmap,
                    color: TackColors.tealText,
                  ),
                ),
              ),
              const SizedBox(width: TackSpace.md),
              Expanded(child: Text('Skills', style: TackText.sectionHeader)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.md,
                  vertical: TackSpace.sm,
                ),
                decoration: BoxDecoration(
                  color: TackColors.tealTint,
                  borderRadius: TackRadius.pillAll,
                ),
                child: Text(
                  '${skills.length} total',
                  style: TackText.body.copyWith(color: TackColors.tealText),
                ),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          Text(
            skills.isEmpty
                ? ProfileSection.skills.emptyHint
                : 'Your toolkit, at a glance.',
            style: TackText.bodyMuted,
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: TackSpace.lg),
            _SkillGroups(skills: preview),
          ],
          if (skills.length > _previewCount) ...[
            const SizedBox(height: TackSpace.md),
            TackButton.ghost(
              'View all ${skills.length} skills',
              icon: TackIcon(
                TackIcons.arrowRight,
                color: TackColors.maroonText,
                size: 20,
              ),
              onPressed: () => showTackSheet<void>(
                context: context,
                title: 'Your skills',
                child: _SkillsLibrary(skills: ordered),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<UserSkill> _ordered(List<UserSkill> skills) => [...skills]
  ..sort((a, b) {
    final level = b.proficiency.compareTo(a.proficiency);
    return level != 0
        ? level
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

class _SkillGroups extends StatelessWidget {
  const _SkillGroups({required this.skills});
  final List<UserSkill> skills;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<UserSkill>>{};
    for (final skill in skills) {
      groups.putIfAbsent(skill.proficiencyLabel, () => []).add(skill);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups.entries) ...[
          if (group.key != groups.keys.first)
            const SizedBox(height: TackSpace.md),
          Container(
            padding: const EdgeInsets.all(TackSpace.lg),
            decoration: BoxDecoration(
              color: TackColors.sailWhite,
              borderRadius: TackRadius.inputAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.key,
                  style: TackText.body.copyWith(color: TackColors.tealText),
                ),
                const SizedBox(height: TackSpace.md),
                Wrap(
                  spacing: TackSpace.sm,
                  runSpacing: TackSpace.sm,
                  children: [
                    for (final skill in group.value)
                      Semantics(
                        label: '${skill.name}, ${skill.proficiencyLabel}',
                        excludeSemantics: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TackSpace.md,
                            vertical: TackSpace.sm,
                          ),
                          decoration: BoxDecoration(
                            color: TackColors.white,
                            borderRadius: TackRadius.inputAll,
                            border: Border.all(color: TackColors.line),
                          ),
                          child: Text(skill.name, style: TackText.body),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SkillsLibrary extends StatefulWidget {
  const _SkillsLibrary({required this.skills});
  final List<UserSkill> skills;

  @override
  State<_SkillsLibrary> createState() => _SkillsLibraryState();
}

class _SkillsLibraryState extends State<_SkillsLibrary> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final skills = widget.skills
        .where((s) => s.name.toLowerCase().contains(_query))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TackSpace.screen,
        0,
        TackSpace.screen,
        MediaQuery.viewInsetsOf(context).bottom + TackSpace.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TackSearchField(
            hint: 'Find a skill',
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: TackSpace.md),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: skills.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: TackSpace.lg,
                      ),
                      child: Text(
                        'Try another skill name.',
                        style: TackText.bodyMuted,
                      ),
                    )
                  : _SkillGroups(skills: skills),
            ),
          ),
          const SizedBox(height: TackSpace.md),
          TackButton.secondary('Done', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
