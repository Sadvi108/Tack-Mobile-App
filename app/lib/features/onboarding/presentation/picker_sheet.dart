import 'package:flutter/material.dart';

import '../../../design/tack.dart';

/// A searchable single-choice list in a bottom sheet.
///
/// A sheet rather than a dropdown menu, because a sheet is reachable with a
/// thumb on a tall phone and a menu anchored to the top of the screen is not.
Future<T?> showPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) labelOf,
  T? selected,
  bool searchable = true,
  String searchHint = 'Search',
}) {
  return showTackSheet<T>(
    context: context,
    title: title,
    child: _PickerBody<T>(
      options: options,
      labelOf: labelOf,
      selected: selected,
      searchable: searchable,
      searchHint: searchHint,
    ),
  );
}

class _PickerBody<T> extends StatefulWidget {
  const _PickerBody({
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.searchable,
    required this.searchHint,
  });

  final List<T> options;
  final String Function(T option) labelOf;
  final T? selected;
  final bool searchable;
  final String searchHint;

  @override
  State<_PickerBody<T>> createState() => _PickerBodyState<T>();
}

class _PickerBodyState<T> extends State<_PickerBody<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.options
        : widget.options.where((o) => widget.labelOf(o).toLowerCase().contains(q)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TackSpace.screen, 0, TackSpace.screen, TackSpace.md,
            ),
            child: TackSearchField(
              hint: widget.searchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        Flexible(
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TackSpace.screen, TackSpace.lg, TackSpace.screen, TackSpace.xl,
                  ),
                  child: Text(
                    'Nothing matches that. Try a shorter search.',
                    style: TackText.bodyMuted,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: TackSpace.lg),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const TackDivider(indent: TackSpace.screen),
                  itemBuilder: (context, i) {
                    final option = visible[i];
                    final isSelected = option == widget.selected;
                    return TackTapRow(
                      onTap: () => Navigator.of(context).pop(option),
                      padding: const EdgeInsets.symmetric(
                        horizontal: TackSpace.screen,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.labelOf(option),
                              style: TackText.rowTitle.copyWith(
                                color: isSelected ? TackColors.maroon : TackColors.ink,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const TackIcon(TackIcons.check, size: 20, color: TackColors.maroon),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
