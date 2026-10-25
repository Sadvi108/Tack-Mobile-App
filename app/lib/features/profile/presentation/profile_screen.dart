import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import 'package:tack/design/tack.dart';
import '../../../routing/router.dart';
import '../application/completeness.dart';
import '../application/profile.dart';
import '../application/profile_sections.dart';
import 'skills_card.dart';
import '../../../routing/tab_bar.dart';

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
    final sectionsAsync = ref.watch(profileSectionsProvider);
    final skillsAsync = ref.watch(userSkillsProvider);
    final sections = sectionsAsync.value ?? const {};
    final skills = skillsAsync.value ?? const <UserSkill>[];
    // Not loaded is not empty. Read as empty, a student with twenty skills
    // was told "Add what you can do" for the second it took them to arrive.
    final sectionsPending = !sectionsAsync.hasValue && sectionsAsync.isLoading;
    final skillsPending = !skillsAsync.hasValue && skillsAsync.isLoading;
    final completeness = ref.watch(completenessProvider).value;
    final mode = ref.watch(modeProvider);
    final atSchool = mode.isAtSchool;
    return TackScaffold(
      bottomNav: const TackTabBar(current: Routes.profile),
      header: TackHeader(
        title: 'Your profile',
        // Settings rather than a sheet of two items. Documents and logging
        // out both live in there now, so keeping a second menu here would be
        // two places to look for the same things.
        trailing: TackGlassIconButton(
          icon: TackIcons.settings,
          onTap: () => context.push(Routes.settings),
          semanticLabel: 'Settings',
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
              _ProfileHero(profile: profile, completeness: completeness),
              const SizedBox(height: TackSpace.stackLoose),

              if (!atSchool) ...[
                if (skillsPending)
                  const TackSkeleton(height: 180, radius: 20)
                else
                  SkillsCard(skills: skills),
                const SizedBox(height: TackSpace.stackLoose),
              ],
              _DirectionCard(profile: profile),
              const SizedBox(height: TackSpace.stackLoose),

              for (final section
                  in atSchool
                      ? ProfileSection.forSchool()
                      : ProfileSection.forUniversity()) ...[
                if (sectionsPending)
                  const TackSkeleton(height: 96, radius: 20)
                else
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

    // The sheet owns its controllers. It used to be the other way round: this
    // method made them, awaited the sheet, and disposed them the moment the
    // await returned — which is when Navigator.pop is called, not when the
    // sheet is gone. The text fields are still mounted through the closing
    // animation, so the next frame rebuilt them against disposed controllers
    // and the screen died. Letting the widget own them hands that ordering to
    // the framework, which is the only thing that actually knows it.
    final values = await showTackSheet<Map<String, String>>(
      context: context,
      title: '${section.saveVerb} ${section.title.toLowerCase()}',
      child: _EntrySheet(fields: fields),
    );

    if (values == null) return;

    final required = fields.first.key;
    if ((values[required] ?? '').isEmpty) return;

    try {
      await ref.read(sectionInsertProvider)(section, {
        for (final entry in values.entries)
          if (entry.value.isNotEmpty)
            entry.key: _coerce(entry.key, entry.value),
      });
      ref
        ..invalidate(profileSectionsProvider)
        ..invalidate(completenessProvider);
      if (context.mounted) {
        TackToast.show(
          context,
          message: section == ProfileSection.education ? 'Updated.' : 'Added.',
        );
      }
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
    // These are education_profiles' own columns. They used to be the old
    // education table's, which is why nothing a student typed here ever
    // reached the record onboarding had already written.
    ProfileSection.education => const [
      _Field(
        'institution_name',
        'Where you study',
        'Your school or university',
      ),
      _Field('expected_end_year', 'Finishing in', '2027'),
      _Field('gpa', 'Your result so far', 'Optional, for example 3.50'),
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

/// Who this is, and how far the profile has to go.
///
/// Completeness is a ring around the avatar rather than a banner of its own: it
/// is a fact about the person, and it reads as one at a glance. The sentence
/// underneath still names what is missing, so it stays a to-do and not a
/// scolding.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile, required this.completeness});

  final Profile profile;
  final ProfileCompleteness? completeness;

  @override
  Widget build(BuildContext context) {
    final c = completeness;
    final place = [
      if (profile.cityName != null) profile.cityName!,
      if (profile.countryName != null) profile.countryName!,
    ].join(', ');

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CompletenessRing(
                initials: profile.initials,
                percent: c?.percent,
              ),
              const SizedBox(width: TackSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName ?? 'Add your name',
                      style: TackText.sectionHeader,
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(place, style: TackText.meta),
                    ],
                    if (profile.displayPhone case final phone?) ...[
                      const SizedBox(height: 2),
                      Text(phone, style: TackText.meta),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          // The mode, and the stage it came from — the second explains the
          // first, which otherwise reads as jargon.
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: 6,
            children: [
              TackPill(
                profile.mode.chipText,
                background: TackColors.maroonTint,
                foreground: TackColors.maroonText,
              ),
              if (profile.stage != null)
                TackPill(
                  profile.stage!.label,
                  background: TackColors.line,
                  foreground: TackColors.muted,
                ),
            ],
          ),
          if (c != null && !c.isComplete) ...[
            const SizedBox(height: TackSpace.lg),
            const TackDivider(),
            const SizedBox(height: TackSpace.lg),
            Text('Profile ${c.percent}% complete', style: TackText.cardTitle),
            const SizedBox(height: TackSpace.sm),
            TackProgressBar(value: c.percent / 100, height: 8),
            const SizedBox(height: TackSpace.md),
            // Names what to do, rather than only how far off it is.
            Text(c.sentence, style: TackText.bodyMuted),
          ],
        ],
      ),
    );
  }
}

/// The avatar, ringed by how complete the profile is. The ring sweeps to its
/// value once when the screen opens and then holds still.
class _CompletenessRing extends StatelessWidget {
  const _CompletenessRing({required this.initials, required this.percent});

  final String initials;
  final int? percent;

  static const _size = 80.0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final target = (percent ?? 0) / 100;

    Widget arc(double value) => CustomPaint(
      size: const Size.square(_size),
      painter: _ArcPainter(
        value: value,
        track: TackColors.line,
        fill: TackColors.teal,
      ),
    );

    return Semantics(
      label: percent == null ? null : 'Profile $percent percent complete',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (percent != null)
              reduceMotion
                  ? arc(target)
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: target),
                      duration: TackMotion.reveal,
                      curve: TackMotion.revealCurve,
                      builder: (context, v, _) => arc(v),
                    ),
            TackAvatar(initials: initials, size: 64),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    canvas.drawArc(
      rect,
      0,
      6.2832,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -1.5708,
      6.2832 * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
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
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(section.title, style: TackText.cardTitle),
                    ),
                    // How many, at a glance, without opening anything.
                    if (entries.isNotEmpty) ...[
                      const SizedBox(width: TackSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TackColors.line,
                          borderRadius: TackRadius.pillAll,
                        ),
                        child: Text(
                          '${entries.length}',
                          style: TackText.pill.copyWith(
                            color: TackColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TackPressable(
                onTap: onAdd,
                scale: 0.88,
                borderRadius: const BorderRadius.all(Radius.circular(22)),
                semanticLabel:
                    '${section.saveVerb} ${section.title.toLowerCase()}',
                excludeSemantics: true,
                child: SizedBox(
                  width: TackSpace.tapTarget,
                  height: TackSpace.tapTarget,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: TackColors.maroonTint,
                        shape: BoxShape.circle,
                      ),
                      child: TackIcon(
                        section == ProfileSection.education
                            ? TackIcons.edit
                            : TackIcons.plus,
                        size: 18,
                        strokeWidth: 2.2,
                        color: TackColors.maroonText,
                      ),
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
            atSchool ? 'WHAT YOU WANT TO STUDY' : 'WHAT YOU ARE AIMING AT',
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
                  TackPill.teal(industry),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Numbers have to arrive as numbers: expected_end_year is an int column and
/// gpa is numeric, and Postgres will not take "2027" for either.
Object? _coerce(String key, String value) => switch (key) {
  'expected_end_year' => int.tryParse(value),
  'gpa' => double.tryParse(value),
  _ => value,
};

/// The add-or-edit sheet.
///
/// A StatefulWidget purely so the controllers have an owner with a lifecycle.
/// It pops the values rather than a flag, so nothing outside it has to read a
/// controller after the sheet is on its way out.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.fields});

  final List<_Field> fields;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields) field.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    // Read while the sheet is still standing, then hand the values out.
    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final required = widget.fields.first.key;
    if ((values[required] ?? '').isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The sheet's own context, so this tracks the keyboard that is actually
      // covering it rather than the insets of the page underneath.
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
          for (final field in widget.fields) ...[
            TackTextField(
              label: field.label,
              hint: field.hint,
              controller: _controllers[field.key],
              maxLines: field.multiline ? 4 : 1,
              textInputAction: field.multiline
                  ? TextInputAction.newline
                  : TextInputAction.next,
            ),
            const SizedBox(height: TackSpace.stack),
          ],
          const SizedBox(height: TackSpace.sm),
          TackButton('Save', onPressed: _save),
        ],
      ),
    );
  }
}
