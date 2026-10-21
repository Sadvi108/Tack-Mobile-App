import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../tokens.dart';
import 'glass.dart';

/// The standard card: a pane of glass over the page. [emphasised] adds a 1.5px
/// maroon border — the design uses a border rather than elevation to mark the
/// single most important card on a screen.
///
/// A maroon [background] makes it a brand pane, lit the same way. Any other
/// [background] is a plain tinted fill, because a tint is already saying
/// something about the card and glass over it would blur what.
///
/// Given an [onTap], the whole card becomes a [TackPressable]: it sinks a
/// little and darkens under a finger, announces itself as a button, and can be
/// reached with a keyboard or switch access.
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
    this.semanticLabel,
  });

  final Widget child;
  final bool emphasised;
  final bool compact;
  final bool raised;
  final EdgeInsets? padding;

  /// Defaults to the card surface for the current palette.
  final Color? background;
  final VoidCallback? onTap;

  /// What a screen reader says for a tappable card. Left null, it reads the
  /// card's own text.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? TackRadius.listCardAll : TackRadius.cardAll;
    // Maroon is dark in both palettes, so only darkening reads on it.
    final onFill =
        background == TackColors.maroon || background == TackColors.maroonDeep;

    final glass = TackGlass.pane(borderRadius: radius);
    final Decoration decoration;
    if (onFill) {
      decoration = TackGlass.brand(borderRadius: radius);
    } else if (background != null) {
      decoration = BoxDecoration(color: background, borderRadius: radius);
    } else if (emphasised) {
      decoration = glass.copyWith(
        border: Border.all(color: TackColors.maroonText, width: 1.5),
      );
    } else {
      decoration = raised
          ? glass.copyWith(boxShadow: TackShadow.glassRaised)
          : glass;
    }

    final content = Container(
      width: double.infinity,
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: compact ? TackSpace.cardCompactX : TackSpace.cardX,
            vertical: compact ? TackSpace.cardCompactY : TackSpace.cardY,
          ),
      decoration: decoration,
      // The rim, in the foreground so it costs no layout. A border in the
      // decoration would push every card's content in by a pixel, and nothing
      // should move when a card changes kind. An emphasised card's maroon
      // border already is its edge, and a tinted card has none.
      foregroundDecoration: emphasised || (background != null && !onFill)
          ? null
          : TackGlass.rim(
              borderRadius: radius,
              colour: onFill ? TackColors.glassRimOnBrand : null,
            ),
      child: child,
    );

    if (onTap == null) return content;

    return TackPressable(
      onTap: onTap,
      borderRadius: radius,
      overlay: onFill ? TackColors.pressOverlayOnFill : TackColors.pressOverlay,
      semanticLabel: semanticLabel,
      child: content,
    );
  }
}

/// Anything a whole surface of which is tappable.
///
/// Three things happen under a finger, and each is there for a reason:
///
///   * it shrinks by [scale] — the part that says "this moved because you
///     touched it", skipped when the platform asks for less motion;
///   * an [overlay] fades in over it — so the press still shows with motion
///     off, and on a surface too small for a scale to register;
///   * or it fades to [pressedOpacity] — for a row inside a card, where a
///     shrinking row would pull away from its dividers.
///
/// The press goes in over [TackMotion.pressIn] and a release waits for that to
/// finish before coming back out. The alternative — tracking the finger
/// exactly — means a quick tap goes down and up within a frame and shows
/// nothing at all, which is the most common tap there is.
class TackPressable extends StatefulWidget {
  const TackPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = BorderRadius.zero,
    this.scale = TackMotion.pressScale,
    this.overlay,
    this.pressedOpacity = 1,
    this.semanticLabel,
    this.excludeSemantics = false,
  });

  final Widget child;

  /// Null makes it inert: no feedback, no button in the semantics tree.
  final VoidCallback? onTap;

  final BorderRadius borderRadius;
  final double scale;
  final Color? overlay;
  final double pressedOpacity;
  final String? semanticLabel;

  /// Replace the child's semantics with [semanticLabel] rather than adding to
  /// them. For a card whose text would read as a jumble of fragments.
  final bool excludeSemantics;

  @override
  State<TackPressable> createState() => _TackPressableState();
}

class _TackPressableState extends State<TackPressable>
    with SingleTickerProviderStateMixin {
  // Made in initState, not lazily. An inert pressable never touches it, and a
  // lazy one was then first created in dispose — asking a deactivated element
  // for its TickerMode, which asserts.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: TackMotion.pressIn,
      reverseDuration: TackMotion.fast,
    );
  }

  bool _held = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  void _hold(bool held) {
    if (_held == held) return;
    _held = held;
    if (held) {
      _c.forward();
      return;
    }
    // Let the press finish going in before it comes back out.
    if (_c.status == AnimationStatus.forward) {
      _c.forward().whenCompleteOrCancel(() {
        if (mounted && !_held) _c.reverse();
      });
    } else {
      _c.reverse();
    }
  }

  @override
  void didUpdateWidget(TackPressable old) {
    super.didUpdateWidget(old);
    if (!_enabled && _held) {
      _held = false;
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final overlay = widget.overlay;

    final pressed = AnimatedBuilder(
      animation: _c,
      child: widget.child,
      // All three wrappers are always present, even when one is doing nothing.
      // Adding one conditionally would change the tree's shape the moment
      // focus arrives or motion is turned off, and remount everything inside
      // the card — restarting its reveal animations mid-read. An identity
      // transform and a full opacity paint straight through without a layer,
      // so the constant shape costs nothing.
      builder: (context, child) {
        final t = TackMotion.curve.transform(_c.value);
        final scale = reduceMotion ? 1.0 : widget.scale;
        return Transform.scale(
          scale: 1 - (1 - scale) * t,
          child: Opacity(
            opacity: 1 - (1 - widget.pressedOpacity) * t,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                color: overlay?.withValues(alpha: overlay.a * t),
                // Only for a keyboard or switch user, never a finger: the
                // platform decides which, through onShowFocusHighlight.
                border: _focused
                    ? Border.all(color: TackColors.maroonText, width: 2)
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );

    return Semantics(
      container: true,
      button: true,
      label: widget.semanticLabel,
      // With [excludeSemantics] the gesture detector's own tap action is
      // excluded along with the child's text, and a button a screen reader can
      // name but not press is worse than one it cannot find — so it is given
      // here instead. Only then: otherwise the detector's action and focus
      // merge into this node as they are, and setting one here as well
      // displaces the focus flag.
      onTap: widget.excludeSemantics ? widget.onTap : null,
      excludeSemantics: widget.excludeSemantics,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _hold(true),
          onTapUp: (_) => _hold(false),
          onTapCancel: () => _hold(false),
          onTap: widget.onTap,
          child: pressed,
        ),
      ),
    );
  }
}

/// The mark in a card's top corner that says the whole card opens something.
///
/// A card that navigates and looks exactly like a card that does not is a
/// guessing game. Press feedback only answers the question after the tap; this
/// answers it before.
class TackCardArrow extends StatelessWidget {
  const TackCardArrow({super.key, this.onBrand = false});

  /// On a maroon card rather than a surface.
  final bool onBrand;

  static const size = 28.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onBrand ? TackColors.onBrandWell : TackColors.sailWhite,
          shape: BoxShape.circle,
        ),
        child: TackIcon(
          TackIcons.chevronRight,
          size: 16,
          strokeWidth: 2.2,
          color: onBrand ? TackColors.onBrand : TackColors.muted,
        ),
      ),
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
/// remember it, and dims under a finger — rows sit between dividers inside a
/// card, where fading reads as pressed and shrinking would read as broken.
class TackTapRow extends StatelessWidget {
  const TackTapRow({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return TackPressable(
      onTap: onTap,
      scale: 1,
      pressedOpacity: 0.55,
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
