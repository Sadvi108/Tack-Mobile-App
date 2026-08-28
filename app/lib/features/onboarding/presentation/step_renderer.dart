import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/data/education_stage.dart';
import '../application/intake_controller.dart';
import '../data/option_repository.dart';
import '../domain/flow_config.dart';

/// Renders whatever the config says this step contains.
///
/// One widget for every step in every branch. A new question is an entry in
/// flow_config.dart, not a new screen and not a new conditional.
class StepRenderer extends ConsumerWidget {
  const StepRenderer({super.key, required this.state});

  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = state.step;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in step.fields) ...[
          _Field(field: field, state: state),
          const SizedBox(height: TackSpace.lg),
        ],
      ],
    );
  }
}

class _Field extends ConsumerWidget {
  const _Field({required this.field, required this.state});

  final FieldSpec field;
  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intakeControllerProvider.notifier);
    final options = ref.read(optionRepositoryProvider);
    final countryId = state.answers['country_id'] as String?;

    Future<List<PickerOption<String>>> load() async {
      final loaded = await options.load(field.options, countryId: countryId);
      return field.notSureOption == null
          ? loaded
          : [notSureOption(field.notSureOption!), ...loaded];
    }

    return switch (field.type) {
      FieldType.text => _TextField(field: field, state: state),
      FieldType.number => _TextField(field: field, state: state, numeric: true),
      FieldType.textArea => _TextField(field: field, state: state, lines: 4),

      FieldType.select || FieldType.searchableSelect => _SelectField(
        field: field,
        state: state,
        load: load,
        onPick: (option) {
          controller.answer(field.key, option.value);
          // Kept alongside the value so the field, and later the review
          // screen, can show a name rather than an id.
          controller.answer('${field.key}__label', option.label);

          // The dial code rides along with the country, which is the only
          // place it is known. The phone field reads it back.
          if (field.key == 'country_id' && option.trailing != null) {
            controller.answer('dial_code', option.trailing);
          }
          // Submit stores the institution by name as well as by id, so a
          // university that is later renamed still reads correctly.
          if (field.key == 'institution_id') {
            controller.answer('institution_name', option.label);
          }
        },
      ),

      FieldType.multiChip => _ChipField(field: field, state: state, load: load),

      FieldType.radioCards => _StageCards(state: state),

      FieldType.rankPicker => _RankField(
        field: field,
        state: state,
        load: load,
      ),

      FieldType.repeatableRows => _RowsField(field: field, state: state),

      FieldType.dateParts => _DateField(field: field, state: state),
    };
  }
}

class _TextField extends ConsumerStatefulWidget {
  const _TextField({
    required this.field,
    required this.state,
    this.numeric = false,
    this.lines = 1,
  });

  final FieldSpec field;
  final IntakeState state;
  final bool numeric;
  final int lines;

  @override
  ConsumerState<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends ConsumerState<_TextField> {
  late final _controller = TextEditingController(
    text: '${widget.state.answers[widget.field.key] ?? ''}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final controller = ref.read(intakeControllerProvider.notifier);
    final dialCode = widget.state.answers['dial_code'] as String?;

    return TackTextField(
      label: field.label,
      hint: field.hint,
      helperText: field.help,
      controller: _controller,
      maxLines: widget.lines,
      minLines: widget.lines > 1 ? widget.lines : null,
      maxLength: field.maxLength,
      keyboardType: widget.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (field.key == 'phone' ? TextInputType.phone : null),
      inputFormatters: widget.numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : (field.key == 'phone'
                ? [FilteringTextInputFormatter.digitsOnly]
                : null),
      // The dial code follows the country rather than being baked in.
      prefix: field.key == 'phone' && dialCode != null
          ? Text(
              dialCode,
              style: TackText.body.copyWith(color: TackColors.muted),
            )
          : null,
      onChanged: (value) => controller.answer(field.key, value),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.field,
    required this.state,
    required this.load,
    required this.onPick,
  });

  final FieldSpec field;
  final IntakeState state;
  final Future<List<PickerOption<String>>> Function() load;
  final ValueChanged<PickerOption<String>> onPick;

  @override
  Widget build(BuildContext context) {
    final value = state.answers[field.key] as String?;
    final label = state.answers['${field.key}__label'] as String?;
    final blocked =
        field.dependsOn != null && state.answers[field.dependsOn!] == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackSelectField<String>(
          label: field.label,
          hint: blocked
              ? 'Choose a country first'
              : (field.hint ?? 'Choose one'),
          value: value,
          valueLabel: (_) => label ?? value ?? '',
          enabled: !blocked,
          onTap: () async {
            final options = await load();
            if (!context.mounted) return;
            final picked = await showSearchPicker<String>(
              context: context,
              title: field.label,
              load: () async => options,
              selected: value,
            );
            if (picked == null) return;
            onPick(
              options.firstWhere(
                (o) => o.value == picked,
                orElse: () => PickerOption(value: picked, label: picked),
              ),
            );
          },
        ),
        if (field.help != null) ...[
          const SizedBox(height: 6),
          Text(field.help!, style: TackText.meta.copyWith(fontSize: 13.5)),
        ],
      ],
    );
  }
}

class _ChipField extends ConsumerStatefulWidget {
  const _ChipField({
    required this.field,
    required this.state,
    required this.load,
  });

  final FieldSpec field;
  final IntakeState state;
  final Future<List<PickerOption<String>>> Function() load;

  @override
  ConsumerState<_ChipField> createState() => _ChipFieldState();
}

class _ChipFieldState extends ConsumerState<_ChipField> {
  late final Future<List<PickerOption<String>>> _options = widget.load();

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final controller = ref.read(intakeControllerProvider.notifier);
    final selected = <String>{
      ...((widget.state.answers[field.key] as List?) ?? const []).map(
        (e) => '$e',
      ),
    };
    final custom = <String>{
      ...((widget.state.answers['${field.key}__custom'] as List?) ?? const [])
          .map((e) => '$e'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: TackText.fieldLabel),
        if (field.help != null) ...[
          const SizedBox(height: 2),
          Text(field.help!, style: TackText.meta.copyWith(fontSize: 13.5)),
        ],
        const SizedBox(height: TackSpace.md),
        FutureBuilder<List<PickerOption<String>>>(
          future: _options,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'That list did not load. Check your connection and try again.',
                style: TackText.fieldError,
              );
            }
            if (!snapshot.hasData) {
              return const Wrap(
                spacing: TackSpace.sm,
                runSpacing: TackSpace.sm,
                children: [
                  TackSkeleton(width: 110, height: 44, radius: 22),
                  TackSkeleton(width: 92, height: 44, radius: 22),
                  TackSkeleton(width: 130, height: 44, radius: 22),
                ],
              );
            }

            final all = snapshot.data!;
            final highlighted = all.where((o) => o.highlighted).toList();
            final rest = all.where((o) => !o.highlighted).toList();

            return TackChipGrid(
              options: [
                ...rest,
                for (final label in custom)
                  PickerOption(value: label, label: label),
              ],
              highlightedFirst: highlighted,
              selected: {...selected, ...custom},
              countNoun: 'picked',
              onToggle: (value) {
                final next = {...selected};
                next.contains(value) ? next.remove(value) : next.add(value);
                controller.answer(field.key, next.toList());
              },
              onAddOwn: (label) {
                controller.answer('${field.key}__custom', [...custom, label]);
                // Submit reads this key. Without it anything a student typed
                // themselves was written to the draft and then dropped.
                if (field.key == 'interests') {
                  controller.answer('custom_interests', [...custom, label]);
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _RankField extends ConsumerStatefulWidget {
  const _RankField({
    required this.field,
    required this.state,
    required this.load,
  });

  final FieldSpec field;
  final IntakeState state;
  final Future<List<PickerOption<String>>> Function() load;

  @override
  ConsumerState<_RankField> createState() => _RankFieldState();
}

class _RankFieldState extends ConsumerState<_RankField> {
  late final Future<List<PickerOption<String>>> _options = widget.load();

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final controller = ref.read(intakeControllerProvider.notifier);
    final ranked = [
      ...((widget.state.answers[field.key] as List?) ?? const []).map(
        (e) => '$e',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: TackText.fieldLabel),
        if (field.help != null) ...[
          const SizedBox(height: 2),
          Text(field.help!, style: TackText.meta.copyWith(fontSize: 13.5)),
        ],
        const SizedBox(height: TackSpace.md),
        FutureBuilder<List<PickerOption<String>>>(
          future: _options,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const TackSkeleton(height: 44, radius: 22);
            }
            return TackRankPicker(
              options: [for (final o in snapshot.data!) o.label],
              ranked: ranked,
              onChanged: (next) => controller.answer(field.key, next),
            );
          },
        ),
      ],
    );
  }
}

class _RowsField extends ConsumerWidget {
  const _RowsField({required this.field, required this.state});

  final FieldSpec field;
  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intakeControllerProvider.notifier);
    final rows = [
      for (final row in (state.answers[field.key] as List?) ?? const [])
        (row as Map).map((k, v) => MapEntry('$k', '$v')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: TackText.fieldLabel),
        if (field.help != null) ...[
          const SizedBox(height: 2),
          Text(field.help!, style: TackText.meta.copyWith(fontSize: 13.5)),
        ],
        const SizedBox(height: TackSpace.md),
        TackRepeatableRows(
          rows: rows,
          maxRows: field.maxRows ?? 8,
          addLabel: '+ Add one',
          emptyMessage: 'Nothing added yet, which is fine.',
          describe: (row) => [
            row['title'] ?? row['role'] ?? '',
            row['code'] ?? row['organisation'] ?? '',
          ].where((s) => s.isNotEmpty).join(' · '),
          onRemove: (index) {
            final next = [...rows]..removeAt(index);
            controller.answer(field.key, next);
          },
          onAdd: () async {
            final row = await _addRow(context, field);
            if (row != null) controller.answer(field.key, [...rows, row]);
          },
        ),
      ],
    );
  }

  Future<Map<String, String>?> _addRow(
    BuildContext context,
    FieldSpec field,
  ) async {
    final controllers = {
      for (final f in field.rowFields) f.key: TextEditingController(),
    };

    final saved = await showTackSheet<bool>(
      context: context,
      title: field.label,
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
            for (final f in field.rowFields) ...[
              TackTextField(
                label: f.label,
                controller: controllers[f.key],
                keyboardType: f.type == FieldType.number
                    ? TextInputType.number
                    : null,
              ),
              const SizedBox(height: TackSpace.stack),
            ],
            const SizedBox(height: TackSpace.sm),
            Builder(
              builder: (sheetContext) => TackButton(
                'Add it',
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
    for (final c in controllers.values) {
      c.dispose();
    }

    if (saved != true) return null;
    final requiredKey = field.rowFields.firstWhere((f) => f.required).key;
    if ((values[requiredKey] ?? '').isEmpty) return null;
    return values;
  }
}

class _DateField extends ConsumerWidget {
  const _DateField({required this.field, required this.state});

  final FieldSpec field;
  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intakeControllerProvider.notifier);
    final year = state.answers['graduation_year'];
    final month = state.answers['graduation_month'];
    final value = year == null
        ? null
        : DateTime(
            year is int ? year : int.tryParse('$year') ?? DateTime.now().year,
            month is int ? month : int.tryParse('$month') ?? 6,
          );

    final thisYear = DateTime.now().year;
    final graduated = state.stage == EducationStage.graduated;

    return TackDateParts(
      label: field.label,
      value: value,
      // A graduate looks backwards; a student looks forwards.
      years: graduated
          ? [for (var y = thisYear + 1; y >= thisYear - 20; y--) y]
          : [for (var y = thisYear; y <= thisYear + 10; y++) y],
      onChanged: (picked) {
        // Every key a date implies, written together — see answersForDate.
        answersForDate(
          fieldKey: field.key,
          year: picked.year,
          month: picked.month,
          monthName: TackDateParts.monthName(picked.month),
        ).forEach(controller.answer);
      },
    );
  }
}

/// The fork. Four large cards, because asking somebody to classify themselves
/// is more expensive than it looks and a dropdown makes it worse.
class _StageCards extends ConsumerWidget {
  const _StageCards({required this.state});

  final IntakeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intakeControllerProvider.notifier);

    return TackRadioCards<String>(
      options: [
        for (final stage in EducationStage.values)
          PickerOption(value: stage.wire, label: stage.label),
      ],
      selected: state.answers['stage'] as String?,
      describe: (wire) => EducationStage.fromWire(wire)?.blurb ?? '',
      onSelect: (wire) => controller.answer('stage', wire),
    );
  }
}
