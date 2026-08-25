import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/readiness.dart';

/// The 90-day score trend.
///
/// Hand-painted rather than pulled from a charting package: it is one
/// polyline, and a charting dependency would cost more download than the whole
/// feature is worth on a slow connection.
class ScoreTrendChart extends StatelessWidget {
  const ScoreTrendChart({super.key, required this.history, this.height = 96});

  final List<ReadinessScore> history;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Your trend appears once you have a few days of history.',
            style: TackText.meta,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totals = [for (final s in history) s.total];
    return Semantics(
      label:
          'Score trend over the last 90 days, from ${totals.first} to ${totals.last}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _TrendPainter(totals)),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.totals);

  final List<int> totals;

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.length < 2) return;

    // Always show a little headroom so a flat line does not sit on the edge.
    final maxValue = totals.reduce((a, b) => a > b ? a : b);
    final minValue = totals.reduce((a, b) => a < b ? a : b);
    final top = (maxValue + 4).clamp(0, 100).toDouble();
    final bottom = (minValue - 4).clamp(0, 100).toDouble();
    final span = (top - bottom) == 0 ? 1.0 : top - bottom;

    Offset pointAt(int i) {
      final x = size.width * i / (totals.length - 1);
      final y = size.height * (1 - (totals[i] - bottom) / span);
      return Offset(x, y);
    }

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < totals.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }

    // A soft fill under the line, then the line itself.
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

    final last = pointAt(totals.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = TackColors.tealText);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.totals != totals;
}
