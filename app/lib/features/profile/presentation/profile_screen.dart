import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../auth/application/auth_controller.dart';
import '../application/completeness.dart';
import '../data/profile.dart';
import '../data/profile_repository.dart';
import '../data/profile_sections.dart';
import '../data/profile_sections_repository.dart';

/// The profile.
///
/// The completeness banner names the two missing things instead of only
/// showing a percentage, so it is a to-do and not a scolding. Each section
/// edits in place — there is no separate edit mode.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final sections = ref.watch(profileSectionsProvider).value ?? const {};
    final skills = ref.watch(userSkillsProvider).value ?? const <UserSkill>[];
    final completeness = ref.watch(completenessProvider).value;
    final mode = ref.watch(modeProvider);
    final atSchool = mode.isAtSchool;
    final tabs = TackTabs.forMode(mode.name);

    return TackScaffold(
      bottomNav: TackBottomNav(
        tabs: tabs,
        currentIndex: tabs.indexWhere((t) => t.route == Routes.profile),
        onTap: (i) => context.go(tabs[i].route),
      ),
      header: TackHeader(
        title: 'Your profile',
        trailing: GestureDetector(
          onTap: () => _menu(context, ref),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(
            width: TackSpace.tapTarget,
            height: TackSpace.tapTarget,
            child: Center(
              child: TackIcon(TackIcons.more, size: 22, color: TackColors.ink),
            ),
          ),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Column(
          children: [
            TackSkeleton(height: 96, radius: 20),
            SizedBox(height: TackSpace.stackLoose),
            TackSkeleton(height: 180, radius: 20),
          ],
        ),
        error: (_, _) => TackErrorState(
          body:
              'Your profile did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (completeness != null && !completeness.isComplete) ...[
                TackCard(
                  emphasised: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Profile ${completeness.percent}% complete',
                              style: TackText.cardTitle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TackSpace.sm),
                      TackProgressBar(
                        value: completeness.percent / 100,
                        height: 8,
                      ),
                      const SizedBox(height: TackSpace.md),
                      // Names what to do, rather than only how far off it is.
                      Text(completeness.sentence, style: TackText.bodyMuted),
                    ],
                  ),
                ),
                const SizedBox(height: TackSpace.stackLoose),
              ],

              _PersonalCard(profile: profile),
              const SizedBox(height: TackSpace.stackLoose),

              if (!atSchool) ...[
                _SkillsCard(skills: skills),
                const SizedBox(height: TackSpace.stackLoose),
              ],
              _DirectionCard(profile: profile),
              const SizedBox(height: TackSpace.stackLoose),

              for (final section
                  in atSchool
                      ? ProfileSection.forSchool()
                      : ProfileSection.forUniversity()) ...[
                _SectionCard(
                  section: section,
                  entries: sections[section] ?? const [],
                  onAdd: () => _add(context, ref, section),
                  onRemove: (id) => _remove(context, ref, section, id),
                ),
                const SizedBox(height: TackSpace.stack),
              ],

              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    ProfileSection section,
  ) async {
    final fields = _fieldsFor(section);
    final controllers = {
      for (final field in fields) field.key: TextEditingController(),
    };

    final saved = await showTackSheet<bool>(
      context: context,
      title: 'Add to ${section.title.toLowerCase()}',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final field in fields) ...[
              TackTextField(
                label: field.label,
                hint: field.hint,
                controller: controllers[field.key],
                maxLines: field.multiline ? 4 : 1,
              ),
              const SizedBox(height: TackSpace.stack),
            ],
            const SizedBox(height: TackSpace.sm),
            Builder(
              builder: (sheetContext) => TackButton(
                'Save',
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ),
          ],
        ),
      ),
    );

    final values = {
      for (final entry in controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved != true) return;

    final required = fields.first.key;
    if ((values[required] ?? '').isEmpty) return;

    try {
      await ref.read(profileSectionsRepositoryProvider).insert(section, {
        for (final entry in values.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      });
      ref
        ..invalidate(profileSectionsProvider)
        ..invalidate(completenessProvider);
      if (context.mounted) TackToast.show(context, message: 'Added.');
    } catch (e) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: Failure.from(e).message,
          kind: TackToastKind.error,
        );
      }
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ProfileSection section,
    String id,
  ) async {
    final confirmed = await confirmTackAction(
      context,
      title: 'Remove this?',
      body: 'It comes off your profile and your readiness score may change.',
      confirmLabel: 'Remove it',
    );
    if (!confirmed) return;

    await ref.read(profileSectionsRepositoryProvider).remove(section, id);
    ref
      ..invalidate(profileSectionsProvider)
      ..invalidate(completenessProvider);
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showTackSheet<String>(
      context: context,
      title: 'Account',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TackTapRow(
            onTap: () => Navigator.of(context).pop('documents'),
            padding: const EdgeInsets.symmetric(
              horizontal: TackSpace.screen,
              vertical: 14,
            ),
            child: Row(
              children: [
                const TackIcon(
                  TackIcons.vault,
                  size: 20,
                  color: TackColors.ink,
                ),
                const SizedBox(width: TackSpace.md),
                Text('Your documents', style: TackText.rowTitle),
              ],
            ),
          ),
          const TackDivider(indent: TackSpace.screen),
          TackTapRow(
            onTap: () => Navigator.of(context).pop('signout'),
            padding: const EdgeInsets.symmetric(
              horizontal: TackSpace.screen,
              vertical: 14,
            ),
            child: Row(
              children: [
                const TackIcon(
                  TackIcons.logout,
                  size: 20,
                  color: TackColors.danger,
                ),
                const SizedBox(width: TackSpace.md),
                Text(
                  'Log out',
                  style: TackText.rowTitle.copyWith(color: TackColors.danger),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.lg),
        ],
      ),
    );

    if (!context.mounted) return;
    if (action == 'documents') context.push(Routes.vault);
    if (action == 'signout') {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  static List<_Field> _fieldsFor(ProfileSection section) => switch (section) {
    // Subjects and hobbies are one word each; the add sheet is a single field.
    ProfileSection.favourites => const [
      _Field(
        'label',
        'Subject or course',
        'Physics, Marketing, Data structures',
      ),
    ],
    ProfileSection.hobbies => const [
      _Field('label', 'What you do', 'Debating, football, editing videos'),
    ],
    ProfileSection.education => const [
      _Field('degree', 'Degree', 'BSc, BBA, BA'),
      _Field('university_name', 'University', 'Where you study'),
      _Field('field_of_study', 'Subject', 'Computer science'),
    ],
    ProfileSection.courses => const [
      _Field('title', 'Course', 'Data structures'),
      _Field('semester', 'Semester', 'Spring 2026'),
      _Field('grade', 'Grade', 'A, optional'),
    ],
    ProfileSection.projects => const [
      _Field('title', 'What you built', 'Shop inventory app'),
      _Field(
        'summary',
        'What it does',
        'One or two sentences',
        multiline: true,
      ),
      _Field('url', 'Link', 'Optional'),
    ],
    ProfileSection.experience => const [
      _Field('title', 'Your role', 'Intern'),
      _Field('company_name', 'Where', 'Company name'),
      _Field('description', 'What you did', 'Optional', multiline: true),
    ],
    ProfileSection.activities => const [
      _Field('title', 'What it was', 'Debate club'),
      _Field('organisation', 'Where', 'Optional'),
      _Field('role', 'Your part in it', 'Optional'),
    ],
    ProfileSection.certifications => const [
      _Field('title', 'Certificate', 'Google Data Analytics'),
      _Field('issuer', 'Who gave it', 'Optional'),
    ],
    ProfileSection.portfolio => const [
      _Field('kind', 'What it is', 'GitHub, LinkedIn, portfolio'),
      _Field('url', 'Link', 'https://…'),
    ],
    ProfileSection.skills => const [],
  };
}

class _Field {
  const _Field(this.key, this.label, this.hint, {this.multiline = false});

  final String key;
  final String label;
  final String hint;
  final bool multiline;
}

class _PersonalCard extends StatelessWidget {
  const _PersonalCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: TackColors.maroon,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: TackText.cardTitle.copyWith(
                color: TackColors.white,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: TackSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName ?? 'Add your name',
                  style: TackText.cardTitle,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (profile.cityName != null) profile.cityName!,
                    if (profile.countryName != null) profile.countryName!,
                  ].join(', '),
                  style: TackText.meta,
                ),
                if (profile.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(profile.phone!, style: TackText.meta),
                ],
                const SizedBox(height: TackSpace.sm),
                // The mode, and the stage it came from — the second explains
                // the first, which otherwise reads as jargon.
                Wrap(
                  spacing: TackSpace.sm,
                  runSpacing: 6,
                  children: [
                    TackPill(profile.mode.chipText),
                    if (profile.stage != null)
                      TackPill(
                        profile.stage!.label,
                        background: TackColors.line,
                        foreground: TackColors.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillsCard extends ConsumerWidget {
  const _SkillsCard({required this.skills});

  final List<UserSkill> skills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HealthDot(
                health: healthFor(ProfileSection.skills, skills.length),
              ),
              const SizedBox(width: TackSpace.sm),
              Expanded(child: Text('Skills', style: TackText.cardTitle)),
              Text('${skills.length}', style: TackText.meta),
            ],
          ),
          if (skills.isEmpty) ...[
            const SizedBox(height: TackSpace.sm),
            Text(ProfileSection.skills.emptyHint, style: TackText.bodyMuted),
          ] else
            for (final skill in skills.take(12)) ...[
              const SizedBox(height: TackSpace.md),
              Row(
                children: [
                  Expanded(child: Text(skill.name, style: TackText.rowTitle)),
                  Text(
                    skill.proficiencyLabel,
                    style: TackText.meta.copyWith(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TackProgressBar(value: skill.proficiency / 5, height: 5),
            ],
          if (skills.length > 12) ...[
            const SizedBox(height: TackSpace.md),
            Text('and ${skills.length - 12} more', style: TackText.meta),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });

  final ProfileSection section;
  final List<ProfileEntry> entries;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HealthDot(health: healthFor(section, entries.length)),
              const SizedBox(width: TackSpace.sm),
              Expanded(child: Text(section.title, style: TackText.cardTitle)),
              GestureDetector(
                onTap: onAdd,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: TackSpace.tapTarget,
                  height: TackSpace.tapTarget,
                  child: Center(
                    child: TackIcon(
                      TackIcons.plus,
                      size: 20,
                      color: TackColors.maroon,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (entries.isEmpty)
            Text(section.emptyHint, style: TackText.bodyMuted)
          else
            for (final entry in entries) ...[
              const TackDivider(),
              TackTapRow(
                onTap: () => onRemove(entry.id),
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.title, style: TackText.rowTitle),
                          if (entry.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(entry.subtitle!, style: TackText.meta),
                          ],
                          if (entry.detail != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry.detail!,
                              style: TackText.bodyMuted,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (entry.meta != null) ...[
                      const SizedBox(width: TackSpace.sm),
                      Text(
                        entry.meta!,
                        style: TackText.meta.copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.health});

  final SectionHealth health;

  @override
  Widget build(BuildContext context) {
    final colour = switch (health) {
      SectionHealth.good => TackColors.teal,
      SectionHealth.thin => TackColors.amber,
      SectionHealth.empty => TackColors.zeroHealth,
    };
    return Semantics(
      label: switch (health) {
        SectionHealth.good => 'In good shape',
        SectionHealth.thin => 'Could use more',
        SectionHealth.empty => 'Nothing here yet',
      },
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
    );
  }
}

/// Where the student is heading, in their own words.
///
/// A school student sees what they want to study and what they enjoy; anyone
/// past school sees the job they are aiming at. Both were collected during
/// onboarding and neither had anywhere to live on this screen before.
class _DirectionCard extends StatelessWidget {
  const _DirectionCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final atSchool = profile.stage?.isAtSchool ?? false;
    final headline = atSchool ? profile.intendedField : profile.targetRole;

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            atSchool ? 'What you want to study' : 'What you are aiming at',
            style: TackText.monoLabel,
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            headline ?? (atSchool ? 'Not decided yet' : 'No target role yet'),
            style: headline == null ? TackText.bodyMuted : TackText.cardTitle,
          ),
          if (atSchool && (profile.passion?.isNotEmpty ?? false)) ...[
            const SizedBox(height: TackSpace.lg),
            Text('WHAT YOU ENJOY', style: TackText.monoLabel),
            const SizedBox(height: TackSpace.sm),
            Text(profile.passion!, style: TackText.body),
          ],
          if (!atSchool && profile.targetIndustry.isNotEmpty) ...[
            const SizedBox(height: TackSpace.lg),
            Text('INDUSTRIES', style: TackText.monoLabel),
            const SizedBox(height: TackSpace.sm),
            Wrap(
              spacing: TackSpace.sm,
              runSpacing: TackSpace.sm,
              children: [
                for (final industry in profile.targetIndustry)
                  TackPill(industry),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
