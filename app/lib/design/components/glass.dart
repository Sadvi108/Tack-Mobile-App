import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';
import 'cards.dart';

/// The page behind the glass: the ground colour and three soft glows.
///
/// Painted once and cached behind a RepaintBoundary, so a list scrolling over
/// it costs a composite and never a repaint. The glows sit still while the
/// panes slide across them, which is most of what makes the panes read as
/// glass rather than as pale cards.
class TackAmbient extends StatelessWidget {
  const TackAmbient({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AmbientPainter(
          ground: TackColors.sailWhite,
          rose: TackColors.glowRose,
          mint: TackColors.glowMint,
          amber: TackColors.glowAmber,
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({
    required this.ground,
    required this.rose,
    required this.mint,
    required this.amber,
  });

  final Color ground;
  final Color rose;
  final Color mint;
  final Color amber;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    void glow(Offset centre, double radius, Color colour) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    // Measured from the width rather than the height, so a tall phone gets
    // the same size of glow as a short one and not a stretched one.
    glow(Offset(w * 0.92, h * 0.02), w * 0.78, rose);
    glow(Offset(w * 0.02, h * 0.42), w * 0.7, mint);
    glow(Offset(w * 0.88, h * 0.7), w * 0.55, amber);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.ground != ground ||
      old.rose != rose ||
      old.mint != mint ||
      old.amber != amber;
}

/// The decorations a glass pane is made of. Everything that draws a pane goes
/// through these, so a card, the tab bar and a header button are the same
/// glass and not three guesses at it.
///
/// Tack draws no shadows, in either palette. A pane is set apart from the page
/// by its fill and its rim, and the one card that matters most on a screen by
/// a maroon border. A drop shadow read as a grey ledge under every card on the
/// pale page, and as a smudge on the dark one.
class TackGlass {
  const TackGlass._();

  /// The pane itself: lit at the top-left, thinner towards the bottom-right.
  static BoxDecoration pane({
    BorderRadius borderRadius = TackRadius.cardAll,
    BoxShape shape = BoxShape.rectangle,
  }) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [TackColors.glassHi, TackColors.glassLo],
    ),
    borderRadius: shape == BoxShape.circle ? null : borderRadius,
    shape: shape,
  );

  /// The rim, drawn in the foreground so it costs no layout.
  static BoxDecoration rim({
    BorderRadius borderRadius = TackRadius.cardAll,
    BoxShape shape = BoxShape.rectangle,
    Color? colour,
  }) => BoxDecoration(
    borderRadius: shape == BoxShape.circle ? null : borderRadius,
    shape: shape,
    border: Border.all(color: colour ?? TackColors.glassRim),
  );

  /// A maroon pane. Still a fill — white text on it is held to AA by the
  /// contrast test — with the brand deepening across it and a faint gloss in
  /// the lit corner.
  static BoxDecoration brand({
    BorderRadius borderRadius = TackRadius.cardAll,
  }) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(TackColors.brandGloss, TackColors.maroon),
        TackColors.maroon,
        TackColors.maroonDeep,
      ],
      stops: const [0, 0.45, 1],
    ),
    borderRadius: borderRadius,
  );
}

/// A round glass button for the corner of a header: back, settings, the bell.
///
/// Forty pixels of glass inside a 44px target, so the edge of the circle is
/// not the edge of what a thumb can hit.
class TackGlassIconButton extends StatelessWidget {
  const TackGlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.badge = false,
    this.iconSize = 20,
  });

  final String icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  /// A dot in the corner — something unread behind this button.
  final bool badge;
  final double iconSize;

  static const _disc = 40.0;

  @override
  Widget build(BuildContext context) {
    return TackPressable(
      onTap: onTap,
      scale: 0.9,
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: TackSpace.tapTarget,
        height: TackSpace.tapTarget,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: _disc,
                height: _disc,
                alignment: Alignment.center,
                decoration: TackGlass.pane(shape: BoxShape.circle),
                foregroundDecoration: TackGlass.rim(shape: BoxShape.circle),
                child: TackIcon(icon, size: iconSize, color: TackColors.ink),
              ),
              if (badge)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: TackColors.maroon,
                      shape: BoxShape.circle,
                      border: Border.all(color: TackColors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One choice in a [TackSegmented].
class TackSegment<T> {
  const TackSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final String? icon;
}

/// Two to four choices side by side, with a thumb that slides to the one
/// picked. For a setting with a handful of answers, where opening a sheet to
/// choose between three words is two taps more than it needs to be.
class TackSegmented<T> extends StatelessWidget {
  const TackSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<TackSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = segments.indexWhere((s) => s.value == selected);

    void pick(int i) {
      if (i == index) return;
      HapticFeedback.selectionClick();
      onChanged(segments[i].value);
    }

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    const inset = 4.0;
    const radius = BorderRadius.all(Radius.circular(14));

    return Container(
      height: 52,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: TackColors.line,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / segments.length;
          return Stack(
            fit: StackFit.expand,
            children: [
              // The thumb moves by transform only: nothing is laid out again
              // while it slides.
              if (index >= 0)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: index.toDouble()),
                  duration: reduceMotion ? Duration.zero : TackMotion.normal,
                  curve: TackMotion.slideCurve,
                  builder: (context, at, child) => Transform.translate(
                    offset: Offset(at * width, 0),
                    child: child,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: width,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: TackColors.white,
                        borderRadius: radius,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < segments.length; i++)
                    Expanded(
                      // The tap is given to the semantics node as well as the
                      // gesture: the node excludes its children so it reads as
                      // one button, and that would otherwise exclude the
                      // gesture's own action with them.
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        label: segments[i].label,
                        onTap: () => pick(i),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => pick(i),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (segments[i].icon case final glyph?) ...[
                                TackIcon(
                                  glyph,
                                  size: 17,
                                  color: i == index
                                      ? TackColors.maroonText
                                      : TackColors.muted,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  segments[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TackText.chip.copyWith(
                                    color: i == index
                                        ? TackColors.ink
                                        : TackColors.muted,
                                    fontWeight: i == index
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
