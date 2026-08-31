import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

/// Every icon in Tack is an inline SVG on a 24×24 viewBox with a 2px stroke
/// and round caps and joins. There is no icon font and no raster asset — this
/// is the whole icon set, and it costs nothing to download.
class TackIcons {
  const TackIcons._();

  static const home =
      '<path d="M2 10.5 12 3l10 7.5"/><rect x="3.5" y="9" width="17" height="11.5" rx="2.5"/>';
  static const roadmap = '<polyline points="3,19 9,11 14,15 21,5"/>';
  static const apply =
      '<rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/>';
  static const vault =
      '<rect x="4" y="3.5" width="16" height="17" rx="2.5"/><path d="M8 9h8M8 13h5"/>';
  static const practice =
      '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.5"/>';
  /// A sweep, not a magnifying glass: Radar keeps watching, it is not a
  /// search box you have to remember to visit.
  static const radar =
      '<path d="M12 3.5a8.5 8.5 0 1 0 8.5 8.5"/><path d="M12 12 18 6"/><circle cx="12" cy="12" r="1.6"/>';

  /// The coach. A speech bubble with a spark: it talks, and it knows things.
  static const coach =
      '<path d="M20.5 11.5a7.5 7.5 0 0 1-7.5 7.5H8l-3.5 2.5V17A7.5 7.5 0 1 1 20.5 11.5Z"/><path d="M12.5 7.5 13.6 10l2.4 1-2.4 1-1.1 2.5-1.1-2.5L9 11l2.4-1z"/>';

  static const paths =
      '<circle cx="12" cy="12" r="9"/><path d="m15 9-2 5-5 2 2-5z"/>';
  static const profile =
      '<circle cx="12" cy="8" r="4"/><path d="M4.5 20a7.5 7.5 0 0 1 15 0"/>';

  static const chevronLeft = '<polyline points="15,5 8,12 15,19"/>';
  static const chevronRight = '<polyline points="9,5 16,12 9,19"/>';
  static const chevronDown = '<polyline points="5,9 12,16 19,9"/>';
  static const chevronUp = '<polyline points="5,15 12,8 19,15"/>';
  static const arrowRight =
      '<path d="M4 12h15"/><polyline points="13,6 19,12 13,18"/>';

  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const check = '<polyline points="4,12.5 9.5,18 20,6.5"/>';
  static const close = '<path d="M6 6l12 12M18 6L6 18"/>';
  static const search =
      '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>';
  static const filter = '<path d="M3 6h18M6.5 12h11M10 18h4"/>';
  static const more =
      '<circle cx="12" cy="5" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="12" cy="19" r="1.4"/>';

  static const upload =
      '<path d="M12 16V4"/><polyline points="6.5,9.5 12,4 17.5,9.5"/><path d="M4 15v3.5A2.5 2.5 0 0 0 6.5 21h11a2.5 2.5 0 0 0 2.5-2.5V15"/>';
  static const download =
      '<path d="M12 4v12"/><polyline points="6.5,10.5 12,16 17.5,10.5"/><path d="M4 18.5A2.5 2.5 0 0 0 6.5 21h11a2.5 2.5 0 0 0 2.5-2.5"/>';
  static const camera =
      '<path d="M4 8.5h3l1.5-2.5h7L17 8.5h3a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 20 19.5H4A1.5 1.5 0 0 1 2.5 18v-8A1.5 1.5 0 0 1 4 8.5Z"/><circle cx="12" cy="13.5" r="3.5"/>';
  static const file =
      '<path d="M14 3H7.5A1.5 1.5 0 0 0 6 4.5v15A1.5 1.5 0 0 0 7.5 21h9a1.5 1.5 0 0 0 1.5-1.5V7z"/><polyline points="14,3 14,7 18,7"/>';
  static const trash =
      '<path d="M4 7h16"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/><path d="M6.5 7l1 12A1.5 1.5 0 0 0 9 20.5h6a1.5 1.5 0 0 0 1.5-1.5l1-12"/>';
  static const edit = '<path d="M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17z"/>';

  static const calendar =
      '<rect x="3.5" y="5.5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3.5v4M16 3.5v4"/>';
  static const clock =
      '<circle cx="12" cy="12" r="8.5"/><polyline points="12,7 12,12 15.5,14"/>';
  static const alert =
      '<path d="M12 4.5 21 19.5H3z"/><path d="M12 10v4M12 17h.01"/>';
  static const info =
      '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>';
  static const shield =
      '<path d="M12 3.5 20 6.5v5.5c0 4.5-3.2 7.6-8 9-4.8-1.4-8-4.5-8-9V6.5z"/>';
  static const bell =
      '<path d="M6.5 10a5.5 5.5 0 0 1 11 0c0 4 1.5 5.5 1.5 5.5H5s1.5-1.5 1.5-5.5Z"/><path d="M10.5 19a1.8 1.8 0 0 0 3 0"/>';
  static const offline =
      '<path d="M3 3l18 18"/><path d="M8.5 14.5a5 5 0 0 1 7 0"/><path d="M5 11a10 10 0 0 1 4-2.4M19 11a10 10 0 0 0-6.5-2.9"/><path d="M12 19h.01"/>';
  static const refresh =
      '<path d="M20 12a8 8 0 1 1-2.4-5.7"/><polyline points="20,4 20,9 15,9"/>';
  static const externalLink =
      '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5.5A1.5 1.5 0 0 1 16.5 21h-11A1.5 1.5 0 0 1 4 19.5v-11A1.5 1.5 0 0 1 5.5 7H11"/>';
  static const logout =
      '<path d="M15 4h3.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H15"/><path d="M11 16l4-4-4-4"/><path d="M15 12H4"/>';
  static const star =
      '<path d="m12 4 2.5 5.2 5.5.8-4 3.9 1 5.6-5-2.7-5 2.7 1-5.6-4-3.9 5.5-.8z"/>';
}

/// Renders one of the [TackIcons] path strings.
class TackIcon extends StatelessWidget {
  const TackIcon(
    this.path, {
    super.key,
    this.size = 24,
    this.color = TackColors.ink,
    this.strokeWidth = 2,
    this.semanticLabel,
  });

  final String path;
  final double size;
  final Color color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" viewBox="0 0 24 24" '
        'fill="none" stroke="$hex" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round">$path</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// The brand mark: a four-segment zigzag ascending left to right with a dot at
/// the end. Tacking is how you make progress toward somewhere you cannot sail
/// at directly — the shape is the product's whole argument.
class TackLogo extends StatelessWidget {
  const TackLogo({super.key, this.width = 34, this.color = TackColors.maroon});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 21 / 34),
      painter: _LogoPainter(color),
      isComplex: false,
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40; // the source viewBox is 40×24
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(3 * s, 21 * s)
      ..lineTo(11 * s, 12 * s)
      ..lineTo(17 * s, 16 * s)
      ..lineTo(25 * s, 7 * s)
      ..lineTo(31 * s, 11 * s);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(36 * s, 5 * s), 3.2 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}

/// Wordmark plus logo, used in the app header and on auth screens.
class TackWordmark extends StatelessWidget {
  const TackWordmark({
    super.key,
    this.color = TackColors.maroon,
    this.fontSize = 18,
  });

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TackLogo(width: fontSize * 1.9, color: color),
        const SizedBox(width: TackSpace.sm),
        Text(
          'Tack',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: -fontSize * 0.01,
            color: color,
          ),
        ),
      ],
    );
  }
}
