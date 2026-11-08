import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../application/toolkit_tools.dart';

/// One tool in the hub: what it is, what it does, and whether it is free.
///
/// The well's colour says which kind of tool it is, using pairs already held
/// to AA in both palettes: practise and ask in maroon, check in teal, the
/// documents in amber.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.tool,
    required this.title,
    required this.body,
    required this.onTap,
    this.free = false,
  });

  final ToolkitTool tool;
  final String title;
  final String body;
  final bool free;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (well, ink) = switch (tool.section) {
      ToolkitSection.practise ||
      ToolkitSection.ask => (TackColors.maroonTint, TackColors.maroonText),
      ToolkitSection.check => (TackColors.tealTint, TackColors.tealText),
      ToolkitSection.store => (TackColors.amberTint, TackColors.amberText),
    };

    return TackCard(
      compact: true,
      onTap: onTap,
      semanticLabel: '$title. $body',
      child: Row(
        children: [
          Container(
            width: TackSpace.tapTarget,
            height: TackSpace.tapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: well,
              borderRadius: TackRadius.buttonAll,
            ),
            child: TackIcon(tool.icon, size: 22, color: ink),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TackText.rowTitle),
                const SizedBox(height: TackSpace.xs),
                Text(body, style: TackText.meta),
                // Under the body, never beside the title: a title that wraps
                // at 360px would push a pill beside it off the card.
                if (free) ...[
                  const SizedBox(height: TackSpace.sm),
                  TackPill.teal('Free'),
                ],
              ],
            ),
          ),
          const SizedBox(width: TackSpace.sm),
          const TackCardArrow(),
        ],
      ),
    );
  }
}
