import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Google's four brand colours as a conic dot. Drawn rather than shipped as an
/// image, so the sign-up screen costs no network request on a slow connection.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GoogleMarkPainter());
}

class _GoogleMarkPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.shortestSide / 2;
    final stroke = size.shortestSide * 0.26;
    final arcRect = Rect.fromCircle(center: centre, radius: radius - stroke / 2);

    void arc(Color colour, double startDeg, double sweepDeg) {
      canvas.drawArc(
        arcRect,
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    arc(_blue, -45, 100);
    arc(_green, 55, 80);
    arc(_yellow, 135, 80);
    arc(_red, 215, 100);

    // The crossbar that makes the mark read as a G rather than a ring.
    canvas.drawRect(
      Rect.fromLTWH(centre.dx, centre.dy - stroke / 2, radius, stroke),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter old) => false;
}
