import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/coach_models.dart';

/// Under a reply answered from Tack's career guides: which guides, each one a
/// tap away. A student can read the source instead of taking the coach's word
/// for it.
class GuideCitations extends StatelessWidget {
  const GuideCitations({super.key, required this.guides, required this.onOpen});

  final List<GuideRef> guides;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "From Tack's career guides",
          style: TackText.meta.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: TackSpace.xs),
        Wrap(
          spacing: TackSpace.sm,
          runSpacing: TackSpace.sm,
          children: [
            for (final guide in guides)
              Semantics(
                button: true,
                label: 'Open the ${guide.title} guide',
                // excludeSemantics hides the pressable's own tap, so the
                // action has to be given again here or a screen reader's
                // double-tap does nothing.
                onTap: () => onOpen(guide.slug),
                excludeSemantics: true,
                child: TackTapRow(
                  onTap: () => onOpen(guide.slug),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TackSpace.md,
                    vertical: TackSpace.sm,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: TackSpace.tapTarget - 2 * TackSpace.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          guide.title,
                          style: TackText.rowTitle.copyWith(
                            color: TackColors.maroonText,
                          ),
                        ),
                        const SizedBox(width: TackSpace.xs),
                        TackIcon(
                          TackIcons.chevronRight,
                          size: 16,
                          color: TackColors.maroonText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
