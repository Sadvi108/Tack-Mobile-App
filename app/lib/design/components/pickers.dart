import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';
import 'cards.dart';
import 'feedback.dart';
import 'fields.dart';
import 'indicators.dart';
import 'pills.dart';

/// One option in a picker.
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.trailing,
    this.highlighted = false,
  });

  final T value;
  final String label;

  /// A dial code, a short name — anything shown quietly on the right.
  final String? trailing;

  /// Pulls the option to the top and marks it. Used for "not sure yet", which
  /// is a real answer and should not be hunted for at the bottom of a list.
  final bool highlighted;
}

/// A search-as-you-type select over a long list.
///
/// Built for lists of a couple of hundred: the sheet renders lazily and the
/// options are fetched only when it opens, so 197 countries and 440 skills
/// never sit in memory waiting for a student who may not open the field.
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required Future<List<PickerOption<T>>> Function() load,
  T? selected,
  String searchHint = 'Search',
  String emptyMessage = 'Nothing matches that. Try a shorter search.',
}) {
  return showTackSheet<T>(
    context: context,
    title: title,
    child: _SearchPickerBody<T>(
      load: load,
      selected: selected,
      searchHint: searchHint,
      emptyMessage: emptyMessage,
    ),
  );
}

class _SearchPickerBody<T> extends StatefulWidget {
  const _SearchPickerBody({
    required this.load,
    required this.selected,
    required this.searchHint,
    required this.emptyMessage,
  });

  final Future<List<PickerOption<T>>> Function() load;
  final T? selected;
  final String searchHint;
  final String emptyMessage;

  @override
  State<_SearchPickerBody<T>> createState() => _SearchPickerBodyState<T>();
}

class _SearchPickerBodyState<T> extends State<_SearchPickerBody<T>> {
  late final Future<List<PickerOption<T>>> _options = widget.load();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TackSpace.screen,
            0,
            TackSpace.screen,
            TackSpace.md,
          ),
          child: TackSearchField(
            hint: widget.searchHint,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Flexible(
          child: FutureBuilder<List<PickerOption<T>>>(
            future: _options,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TackSpace.screen,
                    TackSpace.lg,
                    TackSpace.screen,
                    TackSpace.xl,
                  ),
                  child: Text(
                    'That list did not load. Check your connection and try again.',
                    style: TackText.bodyMuted,
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(
                    TackSpace.screen,
                    TackSpace.md,
                    TackSpace.screen,
                    TackSpace.xl,
                  ),
                  child: Column(
                    children: [
                      TackSkeleton(height: 44, radius: 12),
                      SizedBox(height: TackSpace.sm),
                      TackSkeleton(height: 44, radius: 12),
                      SizedBox(height: TackSpace.sm),
                      TackSkeleton(height: 44, radius: 12),
                    ],
                  ),
                );
              }

              final query = _query.trim().toLowerCase();
              final all = snapshot.data!;
              final visible = query.isEmpty
                  ? all
                  : all
                        .where((o) => o.label.toLowerCase().contains(query))
                        .toList();

              // Highlighted options stay at the top whatever the search.
              visible.sort((a, b) {
                if (a.highlighted == b.highlighted) return 0;
                return a.highlighted ? -1 : 1;
              });

              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TackSpace.screen,
                    TackSpace.lg,
                    TackSpace.screen,
                    TackSpace.xl,
                  ),
                  child: Text(widget.emptyMessage, style: TackText.bodyMuted),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: TackSpace.lg),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const TackDivider(indent: TackSpace.screen),
                itemBuilder: (context, i) {
                  final option = visible[i];
                  final isSelected = option.value == widget.selected;
                  return TackTapRow(
                    onTap: () => Navigator.of(context).pop(option.value),
                    padding: const EdgeInsets.symmetric(
                      horizontal: TackSpace.screen,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: TackText.rowTitle.copyWith(
                              color: isSelected || option.highlighted
                                  ? TackColors.maroon
                                  : TackColors.ink,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (option.trailing != null) ...[
                          const SizedBox(width: TackSpace.sm),
                          Text(option.trailing!, style: TackText.meta),
                        ],
                        if (isSelected) ...[
                          const SizedBox(width: TackSpace.sm),
                          const TackIcon(
                            TackIcons.check,
                            size: 20,
                            color: TackColors.maroon,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Large tappable cards for a question with a handful of consequential
/// answers.
///
/// Asking somebody to classify themselves is more cognitively expensive than
/// it looks, so the targets are big, the wording is plain, and each option
/// carries a line saying what it means.
class TackRadioCards<T> extends StatelessWidget {
  const TackRadioCards({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.describe,
  });

  final List<PickerOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelect;
  final String Function(T value) describe;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options) ...[
          Semantics(
            button: true,
            selected: option.value == selected,
            label: option.label,
            child: GestureDetector(
              onTap: () => onSelect(option.value),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: TackMotion.fast,
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.cardCompactX,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: TackColors.white,
                  borderRadius: TackRadius.listCardAll,
                  border: Border.all(
                    color: option.value == selected
                        ? TackColors.maroon
                        : TackColors.line2,
                    width: option.value == selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    _RadioDot(selected: option.value == selected),
                    const SizedBox(width: TackSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            style: TackText.rowTitle.copyWith(
                              color: option.value == selected
                                  ? TackColors.maroon
                                  : TackColors.ink,
                              fontWeight: option.value == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(describe(option.value), style: TackText.meta),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: TackSpace.row),
        ],
      ],
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

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

/// Pick a few things in order of importance.
///
/// The order is the answer, so the chips show their rank rather than only
/// whether they are on.
class TackRankPicker extends StatelessWidget {
  const TackRankPicker({
    super.key,
    required this.options,
    required this.ranked,
    required this.onChanged,
    this.maxPicks = 3,
  });

  final List<String> options;

  /// Most important first.
  final List<String> ranked;
  final ValueChanged<List<String>> onChanged;
  final int maxPicks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (final option in options)
              _RankChip(
                label: option,
                rank: ranked.indexOf(option),
                onTap: () {
                  final next = [...ranked];
                  if (next.contains(option)) {
                    next.remove(option);
                  } else if (next.length < maxPicks) {
                    next.add(option);
                  } else {
                    // Replace the least important rather than ignoring the tap.
                    next
                      ..removeLast()
                      ..add(option);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
        if (ranked.isNotEmpty) ...[
          const SizedBox(height: TackSpace.md),
          Text(
            ranked.length == 1
                ? 'Most important: ${ranked.first}'
                : 'In order: ${ranked.join(', ')}',
            style: TackText.meta,
          ),
        ],
      ],
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({
    required this.label,
    required this.rank,
    required this.onTap,
  });

  final String label;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = rank >= 0;
    return Semantics(
      button: true,
      selected: picked,
      label: picked ? '$label, ranked ${rank + 1}' : label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.pillAll,
            border: Border.all(
              color: picked ? TackColors.maroon : TackColors.line2,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picked) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: TackColors.maroon,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${rank + 1}',
                    style: TackText.pill.copyWith(
                      color: TackColors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: TackSpace.sm),
              ],
              Text(
                label,
                style: TackText.chip.copyWith(
                  color: picked ? TackColors.maroon : TackColors.ink,
                  fontWeight: picked ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows a student can add and remove: courses, jobs.
///
/// Always skippable. Most students have no experience yet and an empty list
/// should not feel like a blank they failed to fill.
class TackRepeatableRows extends StatelessWidget {
  const TackRepeatableRows({
    super.key,
    required this.rows,
    required this.onAdd,
    required this.onRemove,
    required this.describe,
    required this.addLabel,
    this.maxRows = 8,
    this.emptyMessage,
  });

  final List<Map<String, String>> rows;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String Function(Map<String, String> row) describe;
  final String addLabel;
  final int maxRows;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty && emptyMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: TackSpace.md),
            child: Text(emptyMessage!, style: TackText.bodyMuted),
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: TackSpace.row),
            child: TackCard(
              compact: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(describe(rows[i]), style: TackText.rowTitle),
                  ),
                  GestureDetector(
                    onTap: () => onRemove(i),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: TackSpace.tapTarget,
                      height: TackSpace.tapTarget,
                      child: Center(
                        child: TackIcon(
                          TackIcons.close,
                          size: 18,
                          color: TackColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (rows.length < maxRows)
          TackButton.ghost(addLabel, fullWidth: false, onPressed: onAdd),
      ],
    );
  }
}

/// A month and a year, which is as precise as a graduation date needs to be.
class TackDateParts extends StatelessWidget {
  const TackDateParts({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.years,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final List<int> years;
  final String? errorText;

  static const _months = [
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

  /// The month's name, so a stored date can be shown back as words.
  static String monthName(int month) => _months[month - 1];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TackText.fieldLabel),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TackSelectField<int>(
                hint: 'Month',
                value: value?.month,
                valueLabel: (m) => _months[m - 1],
                onTap: () async {
                  final picked = await showSearchPicker<int>(
                    context: context,
                    title: 'Month',
                    load: () async => [
                      for (var m = 1; m <= 12; m++)
                        PickerOption(value: m, label: _months[m - 1]),
                    ],
                    selected: value?.month,
                  );
                  if (picked != null) {
                    onChanged(DateTime(value?.year ?? years.first, picked));
                  }
                },
              ),
            ),
            const SizedBox(width: TackSpace.sm),
            Expanded(
              flex: 2,
              child: TackSelectField<int>(
                hint: 'Year',
                value: value?.year,
                valueLabel: (y) => '$y',
                onTap: () async {
                  final picked = await showSearchPicker<int>(
                    context: context,
                    title: 'Year',
                    load: () async => [
                      for (final y in years)
                        PickerOption(value: y, label: '$y'),
                    ],
                    selected: value?.year,
                  );
                  if (picked != null) {
                    onChanged(DateTime(picked, value?.month ?? 6));
                  }
                },
              ),
            ),
          ],
        ),
        if (errorText != null && errorText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: TackText.fieldError),
        ],
      ],
    );
  }
}

/// A chip grid with a live count and a way in for anything not listed.
class TackChipGrid extends StatelessWidget {
  const TackChipGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.onAddOwn,
    this.addOwnLabel = '+ Add your own',
    this.countNoun = 'picked',
    this.highlightedFirst = const [],
  });

  final List<PickerOption<String>> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String>? onAddOwn;
  final String addOwnLabel;
  final String countNoun;

  /// Shown first and marked. "Not sure yet" belongs here.
  final List<PickerOption<String>> highlightedFirst;

  @override
  Widget build(BuildContext context) {
    final all = [...highlightedFirst, ...options];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty) ...[
          Text('${selected.length} $countNoun', style: TackText.monoLabel),
          const SizedBox(height: TackSpace.md),
        ],
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (final option in all)
              option.highlighted
                  ? _NotSureChip(
                      label: option.label,
                      selected: selected.contains(option.value),
                      onTap: () => onToggle(option.value),
                    )
                  : TackChip(
                      option.label,
                      selected: selected.contains(option.value),
                      onTap: () => onToggle(option.value),
                    ),
          ],
        ),
        if (onAddOwn != null) ...[
          const SizedBox(height: TackSpace.md),
          TackButton.ghost(
            addOwnLabel,
            fullWidth: false,
            onPressed: () => _addOwn(context),
          ),
        ],
      ],
    );
  }

  Future<void> _addOwn(BuildContext context) async {
    final controller = TextEditingController();
    final entered = await showTackSheet<String>(
      context: context,
      title: 'Add your own',
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
    if (text != null && text.isNotEmpty) onAddOwn!(text);
  }
}

/// "Not sure yet", styled as a real answer rather than a last resort.
class _NotSureChip extends StatelessWidget {
  const _NotSureChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            // Amber rather than grey: not knowing is fine, and the colour
            // should not say otherwise.
            color: selected ? TackColors.amberTint : TackColors.white,
            borderRadius: TackRadius.pillAll,
            border: Border.all(
              color: selected ? TackColors.amberText : TackColors.amber,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const TackIcon(
                  TackIcons.check,
                  size: 15,
                  color: TackColors.amberText,
                  strokeWidth: 2.6,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TackText.chip.copyWith(
                  color: TackColors.amberText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
