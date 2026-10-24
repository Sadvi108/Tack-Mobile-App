import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/checklist_models.dart';

/// What this application still needs, the next step first.
///
/// The rules and their order are `application_checklist` (0082). The first
/// item is the one to do now; the rest wait under it. Nothing to do shows
/// nothing — an empty list on a finished application is noise.
class ChecklistCard extends StatelessWidget {
  const ChecklistCard({
    super.key,
    required this.checklist,
    required this.onAction,
  });

  final Checklist checklist;
  final ValueChanged<ChecklistItem> onAction;

  @override
  Widget build(BuildContext context) {
    final next = checklist.nextStep;
    if (next == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TackCard(
          emphasised: true,
          onTap: () => onAction(next),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next step', style: TackText.monoLabelSmall),
                    const SizedBox(height: TackSpace.xs),
                    Text(next.title, style: TackText.rowTitle),
                  ],
                ),
              ),
              const SizedBox(width: TackSpace.md),
              const TackCardArrow(),
            ],
          ),
        ),
        for (final item in checklist.rest) ...[
          const SizedBox(height: TackSpace.row),
          TackCard(
            compact: true,
            onTap: () => onAction(item),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: TackSpace.md),
                  decoration: BoxDecoration(
                    color: item.isRequired
                        ? TackColors.maroonText
                        : TackColors.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: Text(item.title, style: TackText.body)),
                const SizedBox(width: TackSpace.md),
                const TackCardArrow(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
