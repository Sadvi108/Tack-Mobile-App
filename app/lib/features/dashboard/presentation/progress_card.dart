import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/dashboard_feed.dart';
import 'motion.dart';

/// The score over twelve weeks, and what moved it this one.
///
/// Weekly points rather than daily. The recompute trigger fires within twenty
/// seconds of any write, so a daily line draws the app's own heartbeat; a
/// weekly line draws the student.
///
/// Hand-painted for the same reason [ScoreTrendChart] is: it is one polyline
/// and a fill, and a charting package would cost more to download than this
/// whole card is worth on a slow connection.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.trend,
    required this.weekChange,
    required this.thisWeek,
    required this.lastWeek,
    this.onTap,
  });

  final List<TrendPoint> trend;
  final int weekChange;
  final WeekSummary thisWeek;
  final WeekSummary lastWeek;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAST 12 WEEKS', style: TackText.monoLabelSmall),
                    const SizedBox(height: TackSpace.sm),
                    Text(_headline, style: TackText.cardTitle),
                  ],
                ),
              ),
              if (weekChange != 0) _ChangePill(weekChange),
            ],
          ),
          const SizedBox(height: TackSpace.lg),
          _Sparkline(trend: trend),
          const SizedBox(height: TackSpace.md),
          Text(_sentence, style: TackText.bodyMuted),
        ],
      ),
    );
  }

  String get _headline => switch (weekChange) {
    > 0 => 'Your score is climbing',
    < 0 => 'Your score dipped',
    _ when trend.length < 2 => 'Your score, week by week',
    _ => 'Level this week',
  };

  String get _sentence {
    if (trend.length < 2) {
      return 'The line fills in as the weeks go by. There is nothing to read into a first week.';
    }
    final parts = <String>[
      if (thisWeek.tasksDone > 0)
        '${thisWeek.tasksDone} ${thisWeek.tasksDone == 1 ? 'step' : 'steps'} ticked',
      if (thisWeek.documentsAdded > 0)
        '${thisWeek.documentsAdded} ${thisWeek.documentsAdded == 1 ? 'file' : 'files'} added',
      if (thisWeek.interviewsPractised > 0)
        '${thisWeek.interviewsPractised} practised',
    ];
    if (parts.isEmpty) {
      return lastWeek.isQuiet
          ? 'Nothing added this week or last. One small thing restarts it.'
          : 'Nothing added yet this week. Last week had ${lastWeek.moves}.';
    }
    return '${parts.join(', ')} this week.';
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill(this.change);

  final int change;

  @override
  Widget build(BuildContext context) {
    final up = change > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: up ? TackColors.tealTint : TackColors.maroonTint,
        borderRadius: TackRadius.pillAll,
      ),
      child: TackCountUp(
        change.abs(),
        prefix: up ? '+' : '−',
        suffix: ' this week',
        style: TackText.pill.copyWith(
          color: up ? TackColors.tealText : TackColors.maroonText,
        ),
        semanticsLabel: up
            ? 'Up $change points this week'
            : 'Down ${change.abs()} points this week',
      ),
    );
  }
}

/// The line itself. Sweeps left to right once, then holds.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.trend});

  final List<TrendPoint> trend;

  static const height = 88.0;

  @override
  Widget build(BuildContext context) {
    if (trend.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Your line appears once there are two weeks to join up.',
            style: TackText.meta,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totals = [for (final p in trend) p.total];
    final chart = SizedBox(
      height: height,
      width: double.infinity,
      child: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? CustomPaint(painter: _SparkPainter(totals, 1))
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: TackMotion.reveal,
              curve: TackMotion.revealCurve,
              builder: (context, t, _) =>
                  CustomPaint(painter: _SparkPainter(totals, t)),
            ),
    );

    return Semantics(
      label:
          'Score over ${totals.length} weeks, from ${totals.first} to ${totals.last}',
      excludeSemantics: true,
      child: chart,
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.totals, this.progress);

  final List<int> totals;

  /// 0 to 1. How much of the line has been drawn.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.length < 2) return;

    // Headroom either side, so a flat line does not sit on an edge and a
    // one-point rise does not read as a cliff.
    final maxValue = totals.reduce((a, b) => a > b ? a : b);
    final minValue = totals.reduce((a, b) => a < b ? a : b);
    final top = (maxValue + 6).clamp(0, 100).toDouble();
    final bottom = (minValue - 6).clamp(0, 100).toDouble();
    final span = (top - bottom) == 0 ? 1.0 : top - bottom;

    Offset pointAt(int i) => Offset(
      size.width * i / (totals.length - 1),
      size.height * (1 - (totals[i] - bottom) / span),
    );

    // The sweep is a horizontal clip rather than a partial path: the shape is
    // identical every frame, so nothing is recomputed as it plays.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < totals.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = TackColors.tealTint);

    canvas.drawPath(
      line,
      Paint()
        ..color = TackColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // The head of the line rides the sweep, so the eye has something to follow.
    final head = pointAt(totals.length - 1);
    final travelled = Offset(size.width * progress, 0);
    if (progress >= 1) {
      canvas.drawCircle(head, 4.5, Paint()..color = TackColors.tealText);
    } else if (progress > 0) {
      final y = _yAt(travelled.dx, size, pointAt);
      canvas.drawCircle(
        Offset(travelled.dx, y),
        4.5,
        Paint()..color = TackColors.tealText,
      );
    }
  }

  /// Where the line sits at a given x, so the head can ride it mid-sweep.
  double _yAt(double x, Size size, Offset Function(int) pointAt) {
    final step = size.width / (totals.length - 1);
    final i = (x / step).floor().clamp(0, totals.length - 2);
    final a = pointAt(i);
    final b = pointAt(i + 1);
    final t = step == 0 ? 0.0 : ((x - a.dx) / step).clamp(0.0, 1.0);
    return a.dy + (b.dy - a.dy) * t;
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.totals != totals;
}
