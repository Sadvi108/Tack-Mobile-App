import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/notification_repository.dart';

/// The Monday brief, opened from the updates list: at most three things,
/// strongest first, each with one line on why it matters.
///
/// The order and the wording are the server's (weekly_brief_items, 0080).
/// This only lays them out and says where a tap goes.
class WeeklyBriefSheet extends StatelessWidget {
  const WeeklyBriefSheet({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<BriefItem> items;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    // Scrolls because the sheet stops at 82% of the screen, and three
    // two-line items at a large text size are taller than that.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen,
        0,
        TackSpace.screen,
        TackSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items) ...[
            TackCard(
              compact: true,
              onTap: () => onOpen(item.route),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: TackText.rowTitle),
                        const SizedBox(height: 3),
                        Text(item.why, style: TackText.bodyMuted),
                      ],
                    ),
                  ),
                  const SizedBox(width: TackSpace.md),
                  const TackCardArrow(),
                ],
              ),
            ),
            const SizedBox(height: TackSpace.row),
          ],
        ],
      ),
    );
  }
}
