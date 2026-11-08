import 'package:flutter/material.dart';
import 'package:tack/design/tack.dart';

class PointsCard extends StatelessWidget {
  const PointsCard({
    super.key,
    required this.title,
    required this.items,
    required this.background,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final List<String> items;
  final Color background;
  final String icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: TackSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: TackIcon(icon, size: 17, color: iconColor),
                  ),
                  const SizedBox(width: TackSpace.sm),
                  Expanded(child: Text(item, style: TackText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.stack),
      child: TackCard(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TackText.rowTitle),
            const SizedBox(height: TackSpace.xs),
            Text(body, style: TackText.body),
          ],
        ),
      ),
    );
  }
}

/// What a strong answer covers, as a plain list on a card.
class KeyPointsCard extends StatelessWidget {
  const KeyPointsCard({
    super.key,
    required this.points,
    this.title = 'A strong answer covers',
  });

  final List<String> points;
  final String title;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: TackSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: TackIcon(
                      TackIcons.arrowRight,
                      size: 17,
                      color: TackColors.maroonText,
                    ),
                  ),
                  const SizedBox(width: TackSpace.sm),
                  Expanded(child: Text(point, style: TackText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One key point the student can tick. The whole row is the target, at least
/// 44px tall, and a screen reader hears the point and whether it is ticked.
class KeyPointCheckRow extends StatelessWidget {
  const KeyPointCheckRow({
    super.key,
    required this.point,
    required this.checked,
    required this.onChanged,
  });

  final String point;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: point,
      onTap: () => onChanged(!checked),
      excludeSemantics: true,
      child: TackTapRow(
        onTap: () => onChanged(!checked),
        padding: const EdgeInsets.symmetric(vertical: TackSpace.row),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: TackMotion.fast,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: TackRadius.inputAll,
                border: Border.all(
                  color: checked ? TackColors.maroonText : TackColors.muted,
                  width: checked ? 2 : 1.5,
                ),
              ),
              child: checked
                  ? Center(
                      child: TackIcon(
                        TackIcons.check,
                        size: 16,
                        color: TackColors.maroonText,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: TackSpace.md),
            Expanded(child: Text(point, style: TackText.body)),
          ],
        ),
      ),
    );
  }
}

/// Said wherever a company pack is listed or started (ruling R21).
class PackDisclaimer extends StatelessWidget {
  const PackDisclaimer({super.key, required this.company});

  final String company;

  @override
  Widget build(BuildContext context) => Text(
    'Written by Tack for practice. $company did not write or check these.',
    style: TackText.meta,
  );
}
