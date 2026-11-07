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
