import 'package:flutter/material.dart';
import 'package:tack/design/tack.dart';

import '../application/interview.dart';

/// Choose a role to practise for: browse field, then role, or search by any
/// name a job ad uses ("sqa", "mto"). Null when the sheet is closed.
Future<InterviewRole?> showRolePicker(
  BuildContext context,
  InterviewCatalog catalog,
) => showTackSheet<InterviewRole>(
  context: context,
  title: 'Choose a role',
  child: _RolePicker(catalog: catalog),
);

class _RolePicker extends StatefulWidget {
  const _RolePicker({required this.catalog});

  final InterviewCatalog catalog;

  @override
  State<_RolePicker> createState() => _RolePickerState();
}

class _RolePickerState extends State<_RolePicker> {
  final _query = TextEditingController();
  InterviewField? _field;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final field = _field;

    final List<Widget> rows;
    if (query.isNotEmpty) {
      final hits = widget.catalog.search(query);
      rows = hits.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.screen,
                  vertical: TackSpace.md,
                ),
                child: Text(
                  'No role matches that. Try a shorter word.',
                  style: TackText.bodyMuted,
                ),
              ),
            ]
          : [for (final role in hits) _roleRow(role)];
    } else if (field != null) {
      rows = [
        _Row(
          title: 'All fields',
          leading: TackIcons.chevronLeft,
          onTap: () => setState(() => _field = null),
        ),
        for (final role in field.roles) _roleRow(role),
      ];
    } else {
      rows = [
        for (final f in widget.catalog.fields)
          _Row(
            title: f.name,
            meta: f.roles.length == 1 ? '1 role' : '${f.roles.length} roles',
            trailing: TackIcons.chevronRight,
            onTap: () => setState(() => _field = f),
          ),
      ];
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
          child: TackSearchField(
            hint: 'Search roles',
            controller: _query,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: TackSpace.sm),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: TackSpace.lg),
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _roleRow(InterviewRole role) => _Row(
    title: role.title,
    meta: role.summary.isEmpty ? null : role.summary,
    onTap: () => Navigator.of(context).pop(role),
  );
}

/// One tappable row of the sheet: at least 44px, announced as a button.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.onTap,
    this.meta,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? meta;
  final String? leading;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TackTapRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.screen,
        vertical: TackSpace.row,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            TackIcon(leading!, size: 18, color: TackColors.maroonText),
            const SizedBox(width: TackSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TackText.rowTitle),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(meta!, style: TackText.meta),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: TackSpace.sm),
            TackIcon(trailing!, size: 18, color: TackColors.muted),
          ],
        ],
      ),
    );
  }
}
