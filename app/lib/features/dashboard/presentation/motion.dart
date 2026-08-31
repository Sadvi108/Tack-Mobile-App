import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';

/// Entry animation for one card in the dashboard stack.
///
/// Opacity and a small vertical translate — no scale, no blur, no shadow
/// animation, nothing that forces a repaint of what is underneath. It plays
/// once when the card is first built and then the controller is done, so a
/// student reading the screen is paying nothing for it.
///
/// Respects the platform's reduce-motion setting by skipping straight to the
/// settled state. Motion sickness is not a preference to be talked out of.
class TackReveal extends StatefulWidget {
  const TackReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;

  /// Position in the stack. Each step delays the reveal by [TackMotion.stagger]
  /// so the screen arrives top-down rather than all at once.
  final int index;

  /// How far the card travels, in logical pixels.
  final double offset;

  @override
  State<TackReveal> createState() => _TackRevealState();
}

class _TackRevealState extends State<TackReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: TackMotion.reveal,
  );

  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: TackMotion.revealCurve,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
      return;
    }
    // Staggered rather than simultaneous. Six cards arriving together reads as
    // a flash; six arriving 55ms apart reads as a list being laid down.
    Future<void>.delayed(TackMotion.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      // Built once and reused every frame: the subtree is not rebuilt by the
      // animation, only re-positioned and re-composited.
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A whole number that counts up to its value the first time it is shown, and
/// animates between values after that.
///
/// The count is the point: a score that simply appears is a verdict, and a
/// score that climbs to 34 is a thing that moves — which is the one claim this
/// app most needs a student to believe.
class TackCountUp extends StatelessWidget {
  const TackCountUp(
    this.value, {
    super.key,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.semanticsLabel,
  });

  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final settled = '$prefix$value$suffix';

    // A screen reader should be handed the number, not eleven intermediate
    // ones, so the animation is excluded from semantics entirely.
    return Semantics(
      label: semanticsLabel ?? settled,
      excludeSemantics: true,
      child: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Text(settled, style: style)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: TackMotion.reveal,
              curve: TackMotion.revealCurve,
              builder: (context, v, _) =>
                  Text('$prefix${v.round()}$suffix', style: style),
            ),
    );
  }
}

/// The readiness ring, swept to its value once on arrival.
///
/// [ScoreRing] draws a static arc; this drives its ratio through one curve and
/// then stops. Two widgets rather than a flag on one because most of the app
/// wants the static version and should not pay for a ticker to get it.
class AnimatedScoreRing extends StatelessWidget {
  const AnimatedScoreRing({
    super.key,
    required this.score,
    this.size = 104,
    this.caption,
    this.strokeWidth = 11,
  });

  final int score;
  final double size;
  final String? caption;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return ScoreRing(
        score: score,
        size: size,
        caption: caption,
        strokeWidth: strokeWidth,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: TackMotion.reveal,
      curve: TackMotion.revealCurve,
      builder: (context, v, _) => ScoreRing(
        score: v.round(),
        size: size,
        caption: caption,
        strokeWidth: strokeWidth,
      ),
    );
  }
}
