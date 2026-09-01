import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/roadmap_models.dart';

/// The spine running down the left of the roadmap.
///
/// Hand-painted for the same reason the score ring and the score sparkline are
/// (`indicators.dart`, `progress_card.dart`): it is a line, two arcs and a
/// dot, and a charting package would cost more to download than the whole
/// screen is worth on a slow connection.
///
/// The line itself carries the progress, not only the nodes. It is solid teal
/// behind what is finished, maroon through where the student is now, and a
/// faint hairline ahead — so the shape of how far along you are is readable
/// without counting anything.
class JourneyLine extends StatelessWidget {
  const JourneyLine({
    super.key,
    required this.state,
    this.isFirst = false,
    this.isLast = false,
    this.progress = 0,
  });

  final MilestoneState state;

  final bool isFirst;
  final bool isLast;

  /// How far through the active milestone the student is, 0–1. Only read when
  /// [state] is active — it part-fills the segment below the node so the line
  /// shows progress inside a milestone, not just between them.
  final double progress;

  /// The gutter the spine lives in. The node is centred on it.
  static const width = 34.0;

  @override
  Widget build(BuildContext context) {
    // No height of its own: it takes the height of the milestone beside it,
    // from an IntrinsicHeight row in the screen. A spine that had to be told
    // how tall the card was would go wrong the moment the copy wrapped to
    // another line.
    return SizedBox(
      width: width,
      child: CustomPaint(
        size: Size.infinite,
        painter: _JourneyPainter(
          state: state,
          isFirst: isFirst,
          isLast: isLast,
          progress: progress.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _JourneyPainter extends CustomPainter {
  const _JourneyPainter({
    required this.state,
    required this.isFirst,
    required this.isLast,
    required this.progress,
  });

  final MilestoneState state;
  final bool isFirst;
  final bool isLast;
  final double progress;

  /// Where the node sits from the top of the segment — aligned with the
  /// milestone title rather than centred on the card, so the eye reads
  /// node-and-heading as one thing.
  static const _nodeY = 26.0;
  static const _nodeRadius = 9.0;
  static const _stroke = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;

    Paint line(Color colour) => Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Above the node: the route already travelled.
    if (!isFirst) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, _nodeY - _nodeRadius - 3),
        line(
          state == MilestoneState.locked ? TackColors.line2 : TackColors.teal,
        ),
      );
    }

    // Below the node: the route ahead.
    if (!isLast) {
      final top = _nodeY + _nodeRadius + 3;
      final bottom = size.height;

      switch (state) {
        case MilestoneState.completed:
          canvas.drawLine(
            Offset(x, top),
            Offset(x, bottom),
            line(TackColors.teal),
          );
        case MilestoneState.active:
          // Part-filled: maroon as far as the student has got inside this
          // milestone, faint for the rest of it.
          final split = top + (bottom - top) * progress;
          canvas.drawLine(
            Offset(x, split),
            Offset(x, bottom),
            line(TackColors.line2),
          );
          if (progress > 0) {
            canvas.drawLine(
              Offset(x, top),
              Offset(x, split),
              line(TackColors.maroon),
            );
          }
        case MilestoneState.locked:
          // Dashed, because the route is real but not yet walkable. Drawn as
          // short segments rather than a PathEffect, which Flutter has no
          // cheap equivalent for.
          const dash = 5.0;
          const gap = 5.0;
          var y = top;
          final faint = line(TackColors.line2)..strokeWidth = 2;
          while (y < bottom) {
            canvas.drawLine(
              Offset(x, y),
              Offset(x, (y + dash).clamp(top, bottom)),
              faint,
            );
            y += dash + gap;
          }
      }
    }

    _paintNode(canvas, Offset(x, _nodeY));
  }

  void _paintNode(Canvas canvas, Offset centre) {
    switch (state) {
      case MilestoneState.completed:
        canvas.drawCircle(
          centre,
          _nodeRadius,
          Paint()..color = TackColors.teal,
        );
        // The tick, drawn rather than laid out, so it scales with the node.
        final tick = Path()
          ..moveTo(centre.dx - 4, centre.dy)
          ..lineTo(centre.dx - 1.2, centre.dy + 3)
          ..lineTo(centre.dx + 4.2, centre.dy - 3);
        canvas.drawPath(
          tick,
          Paint()
            ..color = TackColors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

      case MilestoneState.active:
        // A ring with a filled centre — the "you are here" marker. Heavier
        // than the others on purpose; it is the one node that matters.
        canvas.drawCircle(
          centre,
          _nodeRadius,
          Paint()..color = TackColors.maroonTint,
        );
        canvas.drawCircle(
          centre,
          _nodeRadius,
          Paint()
            ..color = TackColors.maroon
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        canvas.drawCircle(
          centre,
          3.4,
          Paint()..color = TackColors.maroon,
        );

      case MilestoneState.locked:
        canvas.drawCircle(
          centre,
          _nodeRadius - 1,
          Paint()..color = TackColors.sailWhite,
        );
        canvas.drawCircle(
          centre,
          _nodeRadius - 1,
          Paint()
            ..color = TackColors.line2
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  @override
  bool shouldRepaint(_JourneyPainter old) =>
      old.state != state ||
      old.isFirst != isFirst ||
      old.isLast != isLast ||
      old.progress != progress;
}
