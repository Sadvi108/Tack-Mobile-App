import 'package:flutter/widgets.dart';

import '../tokens.dart';

/// The standard white card. [emphasised] swaps the resting shadow for a 1.5px
/// maroon border — the design uses a border rather than elevation to mark the
/// single most important card on a screen.
class TackCard extends StatelessWidget {
  const TackCard({
    super.key,
    required this.child,
    this.emphasised = false,
    this.compact = false,
    this.raised = false,
    this.padding,
    this.background,
    this.onTap,
  });

  final Widget child;
  final bool emphasised;
  final bool compact;
  final bool raised;
  final EdgeInsets? padding;

  /// Defaults to the card surface for the current palette.
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: compact ? TackSpace.cardCompactX : TackSpace.cardX,
            vertical: compact ? TackSpace.cardCompactY : TackSpace.cardY,
          ),
      decoration: BoxDecoration(
        color: background ?? TackColors.white,
        borderRadius: compact ? TackRadius.listCardAll : TackRadius.cardAll,
        border: emphasised
            ? Border.all(color: TackColors.maroonText, width: 1.5)
            : null,
        boxShadow: emphasised
            ? null
            : raised
            ? TackShadow.raised
            : TackShadow.resting,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// A hairline divider matching the one used inside cards.
class TackDivider extends StatelessWidget {
  const TackDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: DecoratedBox(decoration: BoxDecoration(color: TackColors.line)),
    ),
  );
}

/// Any tappable row. Enforces the 44px minimum tap target so no caller has to
/// remember it.
class TackTapRow extends StatelessWidget {
  const TackTapRow({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
        child: Padding(
          padding:
              padding ?? const EdgeInsets.symmetric(vertical: TackSpace.sm),
          child: child,
        ),
      ),
    );
  }
}
