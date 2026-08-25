import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/data/profile.dart';
import '../application/onboarding_controller.dart';
import '../data/reference_repository.dart';
import 'picker_sheet.dart';

/// Step 1 — name, city, phone. Three answers, no more.
class StepYou extends ConsumerStatefulWidget {
  const StepYou({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<StepYou> createState() => _StepYouState();
}

class _StepYouState extends ConsumerState<StepYou> {
  late final _name = TextEditingController(text: widget.draft.fullName);
  late final _phone = TextEditingController(text: widget.draft.phone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final cities = ref.watch(citiesProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackTextField(
          label: 'Your name',
          hint: 'As it should appear on your CV',
          controller: _name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onChanged: (v) => controller.patch((d) => d.copyWith(fullName: v)),
        ),
        const SizedBox(height: TackSpace.stack),
        cities.when(
          loading: () => const TackSkeleton(height: 52, radius: 12),
          error: (_, _) => Text(
            'The city list did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (list) => TackSelectField<City>(
            label: 'Where you live',
            hint: 'Choose your city',
            value: list.where((c) => c.id == draft.cityId).firstOrNull,
            valueLabel: (c) => c.name,
            onTap: () async {
              final picked = await showPickerSheet<City>(
                context: context,
                title: 'Your city',
                options: list,
                labelOf: (c) => c.name,
                selected: list.where((c) => c.id == draft.cityId).firstOrNull,
                searchHint: 'Search cities',
              );
              if (picked != null) {
                controller.patch((d) => d.copyWith(cityId: picked.id));
              }
            },
          ),
        ),
        const SizedBox(height: TackSpace.stack),
        TackTextField(
          label: 'Phone number',
          hint: '712345678',
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          prefix: Text(
            '+880',
            style: TackText.body.copyWith(color: TackColors.muted),
          ),
          helperText: 'We only use this if an employer needs to reach you.',
          onChanged: (v) => controller.patch((d) => d.copyWith(phone: v)),
        ),
      ],
    );
  }
}

/// Step 2 — university, degree, graduation year, optional CGPA.
class StepEducation extends ConsumerStatefulWidget {
  const StepEducation({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends ConsumerState<StepEducation> {
  late final _degree = TextEditingController(text: widget.draft.degree);
  late final _field = TextEditingController(text: widget.draft.fieldOfStudy);
  late final _cgpa = TextEditingController(
    text: widget.draft.cgpa?.toStringAsFixed(2) ?? '',
  );
  late final _otherUniversity = TextEditingController(
    text: widget.draft.universityName,
  );

  bool _useOther = false;

  @override
  void dispose() {
    _degree.dispose();
    _field.dispose();
    _cgpa.dispose();
    _otherUniversity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final universities = ref.watch(universitiesProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final thisYear = DateTime.now().year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        universities.when(
          loading: () => const TackSkeleton(height: 52, radius: 12),
          error: (_, _) => Text(
            'The university list did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (list) => TackSelectField<University>(
            label: 'University',
            hint: 'Choose your university',
            value: list.where((u) => u.id == draft.universityId).firstOrNull,
            valueLabel: (u) => u.display,
            onTap: () async {
              final picked = await showPickerSheet<University>(
                context: context,
                title: 'Your university',
                options: list,
                labelOf: (u) => u.display,
                selected: list
                    .where((u) => u.id == draft.universityId)
                    .firstOrNull,
                searchHint: 'Search universities',
              );
              if (picked == null) return;
              final isOther = picked.name == 'Other';
              setState(() => _useOther = isOther);
              controller.patch(
                (d) => d.copyWith(
                  universityId: isOther ? null : picked.id,
                  universityName: isOther ? d.universityName : picked.name,
                ),
              );
            },
          ),
        ),
        if (_useOther ||
            (draft.universityId == null &&
                draft.universityName.isNotEmpty)) ...[
          const SizedBox(height: TackSpace.row),
          TackTextField(
            hint: 'Type your university name',
            controller: _otherUniversity,
            onChanged: (v) =>
                controller.patch((d) => d.copyWith(universityName: v)),
          ),
        ],
        const SizedBox(height: TackSpace.stack),
        TackTextField(
          label: 'Degree',
          hint: 'BSc, BBA, BA and so on',
          controller: _degree,
          textInputAction: TextInputAction.next,
          onChanged: (v) => controller.patch((d) => d.copyWith(degree: v)),
        ),
        const SizedBox(height: TackSpace.stack),
        TackTextField(
          label: 'Subject',
          hint: 'Computer science, finance, English…',
          controller: _field,
          textInputAction: TextInputAction.next,
          onChanged: (v) =>
              controller.patch((d) => d.copyWith(fieldOfStudy: v)),
        ),
        const SizedBox(height: TackSpace.stack),
        TackSelectField<int>(
          label: 'Graduation year',
          hint: 'Choose a year',
          value: draft.graduationYear,
          valueLabel: (y) => '$y',
          onTap: () async {
            final years = [
              for (var y = thisYear - 2; y <= thisYear + 8; y++) y,
            ];
            final picked = await showPickerSheet<int>(
              context: context,
              title: 'Graduation year',
              options: years,
              labelOf: (y) => '$y',
              selected: draft.graduationYear,
              searchable: false,
            );
            if (picked != null) {
              controller.patch((d) => d.copyWith(graduationYear: picked));
            }
          },
        ),
        const SizedBox(height: TackSpace.stack),
        TackTextField(
          label: 'CGPA (optional)',
          hint: '3.45',
          controller: _cgpa,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          helperText: 'Never shown to anyone. It only feeds your own score.',
          onChanged: (v) {
            final parsed = double.tryParse(v);
            controller.patch(
              (d) => parsed == null
                  ? d.copyWith(clearCgpa: true)
                  : d.copyWith(cgpa: parsed.clamp(0, 5)),
            );
          },
        ),
      ],
    );
  }
}

/// Step 3 — the single most important answer in the app. It derives the mode,
/// which decides what every dashboard leads with, so the consequence is shown
/// back before the student moves on.
class StepYear extends ConsumerWidget {
  const StepYear({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final thisYear = DateTime.now().year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Which year are you in?', style: TackText.fieldLabel),
        const SizedBox(height: TackSpace.sm),
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (var y = 1; y <= draft.yearsTotal; y++)
              TackChip(
                y == draft.yearsTotal ? 'Final year' : 'Year $y',
                selected: draft.yearOfStudy == y,
                onTap: () =>
                    controller.patch((d) => d.copyWith(yearOfStudy: y)),
              ),
          ],
        ),
        const SizedBox(height: TackSpace.lg),
        TackSelectField<int>(
          label: 'How long is your programme?',
          hint: 'Choose a length',
          value: draft.yearsTotal,
          valueLabel: (y) => '$y years',
          onTap: () async {
            final picked = await showPickerSheet<int>(
              context: context,
              title: 'Programme length',
              options: const [2, 3, 4, 5, 6],
              labelOf: (y) => '$y years',
              selected: draft.yearsTotal,
              searchable: false,
            );
            if (picked == null) return;
            controller.patch(
              (d) => d.copyWith(
                yearsTotal: picked,
                yearOfStudy: d.yearOfStudy != null && d.yearOfStudy! > picked
                    ? picked
                    : d.yearOfStudy,
              ),
            );
          },
        ),
        const SizedBox(height: TackSpace.stack),
        TackSelectField<DateTime>(
          label: 'When do you expect to graduate?',
          hint: 'Choose a month',
          value: draft.expectedGraduation,
          valueLabel: _monthLabel,
          onTap: () async {
            final months = <DateTime>[
              for (var y = thisYear; y <= thisYear + 8; y++)
                for (final m in const [1, 4, 7, 10]) DateTime(y, m, 1),
            ];
            final picked = await showPickerSheet<DateTime>(
              context: context,
              title: 'Expected graduation',
              options: months,
              labelOf: _monthLabel,
              selected: draft.expectedGraduation,
              searchable: false,
            );
            if (picked != null) {
              controller.patch((d) => d.copyWith(expectedGraduation: picked));
            }
          },
        ),
        if (draft.yearOfStudy != null) ...[
          const SizedBox(height: TackSpace.lg),
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
                    _modeExplanation(draft.previewMode),
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

  static String _monthLabel(DateTime d) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[d.month - 1]} ${d.year}';
  }

  static String _modeExplanation(YearMode mode) => switch (mode) {
    YearMode.explore =>
      'Tack will help you explore what careers exist and try things, and will not talk to you '
          'about applying yet.',
    YearMode.build =>
      'Tack will focus on building real skills and your first project this year.',
    YearMode.prove =>
      'Tack will focus on internships, your portfolio and the people you know.',
    YearMode.launch =>
      'Tack will focus on applications, deadlines and interview practice.',
  };
}
