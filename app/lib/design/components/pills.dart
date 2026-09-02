import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';

/// The six application statuses, plus the tints each one carries.
enum TackStatus { saved, applied, assessment, interview, offer, rejected }

extension TackStatusStyle on TackStatus {
  String get label => switch (this) {
    TackStatus.saved => 'Saved',
    TackStatus.applied => 'Applied',
    TackStatus.assessment => 'Assessment',
    TackStatus.interview => 'Interview',
    TackStatus.offer => 'Offer',
    TackStatus.rejected => 'Rejected',
  };

  String get wire => name;

  Color get background => switch (this) {
    TackStatus.saved => TackColors.line,
    TackStatus.applied => TackColors.maroonTint,
    TackStatus.assessment => TackColors.blueTint,
    TackStatus.interview => TackColors.amberTint,
    TackStatus.offer => TackColors.tealTint,
    TackStatus.rejected => TackColors.maroonTint,
  };

  Color get foreground => switch (this) {
    TackStatus.saved => TackColors.muted,
    TackStatus.applied => TackColors.maroonText,
    TackStatus.assessment => TackColors.blueText,
    TackStatus.interview => TackColors.amberText,
    TackStatus.offer => TackColors.tealText,
    TackStatus.rejected => TackColors.dangerText,
  };

  static TackStatus fromWire(String value) => TackStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TackStatus.saved,
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});

  final TackStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: TackRadius.pillAll,
      ),
      child: Text(
        status.label,
        style: TackText.pill.copyWith(color: status.foreground),
      ),
    );
  }
}

/// A tinted label: point values, skill matches, counts. Not tappable.
class TackPill extends StatelessWidget {
  const TackPill(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.icon,
  });

  TackPill.teal(String label, {Key? key})
    : this(
        label,
        key: key,
        background: TackColors.tealTint,
        foreground: TackColors.tealText,
      );

  TackPill.amber(String label, {Key? key})
    : this(
        label,
        key: key,
        background: TackColors.amberTint,
        foreground: TackColors.amberText,
      );

  final String label;
  final Color? background;
  final Color? foreground;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 11 : 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: TackRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            TackIcon(icon!, size: 13, color: foreground, strokeWidth: 2.4),
            const SizedBox(width: 5),
          ],
          Text(label, style: TackText.pill.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// A selectable chip. 44px minimum height, and a leading tick when selected —
/// colour alone is never the only signal.
class TackChip extends StatelessWidget {
  const TackChip(
    this.label, {
    super.key,
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
          curve: TackMotion.curve,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.pillAll,
            border: Border.all(
              color: selected ? TackColors.maroonText : TackColors.line2,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                TackIcon(
                  TackIcons.check,
                  size: 15,
                  color: TackColors.maroonText,
                  strokeWidth: 2.6,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TackText.chip.copyWith(
                  color: selected ? TackColors.maroonText : TackColors.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filter strip above the application list. The counts double as the
/// filter, so one row does two jobs on a 360px screen.
class CountFilterChip extends StatelessWidget {
  const CountFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? TackColors.maroon : TackColors.white,
            borderRadius: TackRadius.pillAll,
            border: selected
                ? null
                : Border.all(color: TackColors.line2, width: 1),
          ),
          child: Text(
            '$label $count',
            style: TackText.pill.copyWith(
              color: selected ? TackColors.onBrand : TackColors.muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
