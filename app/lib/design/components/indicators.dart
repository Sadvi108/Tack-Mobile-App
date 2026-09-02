import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens.dart';
import '../typography.dart';

/// The readiness score ring. Teal fill over a neutral track, with the number
/// and an optional caption in the middle.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.max = 100,
    this.size = 104,
    this.strokeWidth = 11,
    this.caption,
    this.fill,
    this.track,
    this.numberColor,
    this.background,
  });

  final int score;
  final int max;
  final double size;
  final double strokeWidth;
  final String? caption;
  final Color? fill;
  final Color? track;
  final Color? numberColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ratio = max == 0 ? 0.0 : (score / max).clamp(0.0, 1.0);
    return Semantics(
      label: 'Readiness score $score of $max',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            ratio: ratio,
            strokeWidth: strokeWidth,
            fill: fill ?? TackColors.teal,
            track: track ?? TackColors.line,
            background: background ?? TackColors.white,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: TackText.heroNumber.copyWith(
                    fontSize: size * 0.29,
                    color: numberColor ?? TackColors.maroonText,
                  ),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      caption!,
                      style: TackText.tabLabel.copyWith(fontSize: size * 0.105),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.ratio,
    required this.strokeWidth,
    required this.fill,
    required this.track,
    required this.background,
  });

  final double ratio;
  final double strokeWidth;
  final Color fill;
  final Color track;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    canvas.drawCircle(
      centre,
      size.shortestSide / 2,
      Paint()..color = background,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        -math.pi / 2,
        2 * math.pi * ratio,
        false,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ratio != ratio || old.fill != fill || old.track != track;
}

/// A flat progress bar. Used for roadmap progress, skill proficiency and the
/// score breakdown rows.
class TackProgressBar extends StatelessWidget {
  const TackProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.track,
    this.width,
    this.animate = true,
  });

  /// A health-coloured bar: teal when doing well, amber when partial, and a
  /// muted rose when the component has scored nothing at all.
  factory TackProgressBar.health({
    Key? key,
    required double value,
    double height = 6,
    double? width,
  }) {
    final color = value <= 0
        ? TackColors.zeroHealth
        : value >= 0.7
        ? TackColors.teal
        : TackColors.amber;
    return TackProgressBar(
      key: key,
      value: value,
      height: height,
      width: width,
      color: color,
    );
  }

  final double value;
  final double height;
  final Color? color;
  final Color? track;
  final double? width;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: track ?? TackColors.line,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v == 0 ? 0.0001 : v,
            child: AnimatedContainer(
              duration: animate ? TackMotion.normal : Duration.zero,
              curve: TackMotion.curve,
              decoration: BoxDecoration(
                color: v == 0
                    ? const Color(0x00000000)
                    : (color ?? TackColors.teal),
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The onboarding progress bar: one segment per step.
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({
    super.key,
    required this.total,
    required this.current,
    this.height = 4,
    this.gap = 6,
  });

  final int total;
  final int current;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $current of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: AnimatedContainer(
                duration: TackMotion.normal,
                height: height,
                decoration: BoxDecoration(
                  color: i < current ? TackColors.maroonText : TackColors.line2,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading placeholder. A single quiet pulse — no shimmer sweep, which costs a
/// repaint per frame on the phones this app targets.
class TackSkeleton extends StatefulWidget {
  const TackSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<TackSkeleton> createState() => _TackSkeletonState();
}

class _TackSkeletonState extends State<TackSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.85).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: TackColors.line,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
