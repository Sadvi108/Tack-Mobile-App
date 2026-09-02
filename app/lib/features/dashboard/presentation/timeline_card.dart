import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/dashboard_feed.dart';

/// Everything with a date on it, in one list.
///
/// Three tables feed this — roadmap tasks, application follow-ups and closing
/// dates — and they used to be three separate cards on three separate reads.
/// A student does not think in tables; they think about what is happening this
/// week, so it is one list sorted by date.
///
/// Dates are always relative. "Tomorrow" is something a student can act on;
/// "12 Sep" makes them do the subtraction themselves, and the day they get it
/// wrong is the day they miss something.
class TimelineCard extends StatelessWidget {
  const TimelineCard({
    super.key,
    required this.entries,
    required this.today,
    required this.onOpen,
    this.title = 'Coming up',
    this.emptyBody,
    this.max = 4,
  });

  final List<TimelineEntry> entries;
  final DateTime today;
  final void Function(TimelineEntry entry) onOpen;
  final String title;
  final String? emptyBody;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = entries.take(max).toList();

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TackText.cardTitle)),
              if (entries.length > shown.length)
                Text(
                  '+${entries.length - shown.length} more',
                  style: TackText.meta,
                ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          if (shown.isEmpty)
            Text(
              emptyBody ??
                  'Nothing has a date on it yet. Dates appear here as you set them.',
              style: TackText.bodyMuted,
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const TackDivider(),
              _Row(
                entry: shown[i],
                today: today,
                onTap: () => onOpen(shown[i]),
              ),
            ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.today, required this.onTap});

  final TimelineEntry entry;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = entry.daysFrom(today);
    final soon = days <= 1;
    final when = entry.relativeTo(today);

    // Amber for today and tomorrow, maroon once it is late, muted otherwise.
    // Both of the coloured cases use the audited text colour, never the fill.
    final whenColour = entry.isOverdue
        ? TackColors.maroon
        : soon
        ? TackColors.amberText
        : TackColors.muted;

    return Semantics(
      button: true,
      label: '${entry.title}. ${entry.kind.label}. $when.',
      excludeSemantics: true,
      child: TackTapRow(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A fixed gutter so the titles line up into a column no matter how
            // long the relative dates are.
            SizedBox(
              width: 74,
              child: Text(
                when,
                style: TackText.pill.copyWith(color: whenColour, fontSize: 13),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TackText.rowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle!,
                      style: TackText.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: TackSpace.sm),
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: TackIcon(
                TackIcons.chevronRight,
                size: 16,
                color: TackColors.strokeFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
