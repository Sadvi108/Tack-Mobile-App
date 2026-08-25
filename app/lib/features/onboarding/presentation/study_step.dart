import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/data/education_stage.dart';
import '../application/onboarding_controller.dart';
import '../data/reference_repository.dart';
import 'picker_sheet.dart';

/// Where you study, and how it is going.
///
/// One widget, two quite different forms. A school student is asked for their
/// school, their class and their result; a university student for their
/// institution, degree and year. Neither is shown a field that does not apply
/// to them, which is the entire reason onboarding branches.
class StudyStep extends ConsumerStatefulWidget {
  const StudyStep({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<StudyStep> createState() => _StudyStepState();
}

class _StudyStepState extends ConsumerState<StudyStep> {
  late final _institution = TextEditingController(
    text: widget.draft.institutionName,
  );
  late final _degree = TextEditingController(text: widget.draft.degree);
  late final _field = TextEditingController(text: widget.draft.fieldOfStudy);
  late final _grade = TextEditingController(text: widget.draft.currentGrade);
  late final _cgpa = TextEditingController(
    text: widget.draft.cgpa?.toStringAsFixed(2) ?? '',
  );

  @override
  void dispose() {
    _institution.dispose();
    _degree.dispose();
    _field.dispose();
    _grade.dispose();
    _cgpa.dispose();
    super.dispose();
  }

  static const _classLevels = [
    'Class 9',
    'Class 10 (SSC)',
    'Class 11 (HSC first year)',
    'Class 12 (HSC second year)',
    'O levels',
    'A levels',
    'Diploma',
  ];

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final thisYear = DateTime.now().year;

    if (draft.isAtSchool) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackTextField(
            label: 'Your school or college',
            hint: 'Where you study now',
            controller: _institution,
            textInputAction: TextInputAction.next,
            onChanged: (v) =>
                controller.patch((d) => d.copyWith(institutionName: v)),
          ),
          const SizedBox(height: TackSpace.stack),
          TackSelectField<String>(
            label: 'Which class',
            hint: 'Choose your class',
            value: draft.classLevel,
            valueLabel: (c) => c,
            onTap: () async {
              final picked = await showPickerSheet<String>(
                context: context,
                title: 'Which class',
                options: _classLevels,
                labelOf: (c) => c,
                selected: draft.classLevel,
                searchable: false,
              );
              if (picked != null) {
                controller.patch((d) => d.copyWith(classLevel: picked));
              }
            },
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'Your last result (optional)',
            hint: 'A+, 4.83, 82% — however yours is written',
            controller: _grade,
            helperText: 'Never shown to anyone. It only feeds your own score.',
            onChanged: (v) =>
                controller.patch((d) => d.copyWith(currentGrade: v)),
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'GPA (optional)',
            hint: '4.83',
            controller: _cgpa,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            helperText: 'Out of 5, as most Bangladeshi boards grade.',
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

    // Bachelor's and graduate share a form; only the year question differs.
    final universities = ref.watch(universitiesProvider);
    final isGraduate = draft.stage == EducationStage.graduated;

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
            label: isGraduate ? 'Where you studied' : 'University',
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
              _institution.text = isOther ? '' : picked.name;
              controller.patch(
                (d) => isOther
                    ? d.copyWith(clearUniversity: true, institutionName: '')
                    : d.copyWith(
                        universityId: picked.id,
                        institutionName: picked.name,
                      ),
              );
            },
          ),
        ),
        if (draft.universityId == null) ...[
          const SizedBox(height: TackSpace.row),
          TackTextField(
            hint: 'Type your university name',
            controller: _institution,
            onChanged: (v) =>
                controller.patch((d) => d.copyWith(institutionName: v)),
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

        if (isGraduate)
          TackSelectField<int>(
            label: 'Graduated in',
            hint: 'Choose a year',
            value: draft.graduationYear,
            valueLabel: (y) => '$y',
            onTap: () async {
              final years = [
                for (var y = thisYear + 1; y >= thisYear - 15; y--) y,
              ];
              final picked = await showPickerSheet<int>(
                context: context,
                title: 'Graduated in',
                options: years,
                labelOf: (y) => '$y',
                selected: draft.graduationYear,
                searchable: false,
              );
              if (picked != null) {
                controller.patch((d) => d.copyWith(graduationYear: picked));
              }
            },
          )
        else ...[
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
                  // A student who says year 5 then corrects the programme to
                  // four years must not be left claiming a year that does not
                  // exist.
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
            valueLabel: monthLabel,
            onTap: () async {
              final months = <DateTime>[
                for (var y = thisYear; y <= thisYear + 8; y++)
                  for (final m in const [1, 4, 7, 10]) DateTime(y, m, 1),
              ];
              final picked = await showPickerSheet<DateTime>(
                context: context,
                title: 'Expected graduation',
                options: months,
                labelOf: monthLabel,
                selected: draft.expectedGraduation,
                searchable: false,
              );
              if (picked != null) {
                controller.patch((d) => d.copyWith(expectedGraduation: picked));
              }
            },
          ),
        ],
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

String monthLabel(DateTime d) {
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
