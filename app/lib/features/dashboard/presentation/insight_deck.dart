import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../application/insights.dart';

/// The suggestion deck: the app's answer to "what should I be doing".
///
/// A horizontal deck rather than a stacked list, for one reason — the cards are
/// ranked, and a list makes every card look equally worth reading. Swiping is a
/// choice to see the next one, so the first card keeps the weight it earned by
/// being first, and four more suggestions cost no vertical space on a 640px
/// screen where vertical space is the scarce thing.
///
/// It is full-bleed on the right on purpose, and it is the only thing on the
/// dashboard that is. The next card has to run off the edge of the screen to
/// read as "there is more"; clipped inside the screen's 20px gutter it reads as
/// a rendering bug, which is exactly how it looked before this was fixed.
class InsightDeck extends StatefulWidget {
  const InsightDeck({super.key, required this.insights, required this.onOpen});

  final List<Insight> insights;
  final void Function(Insight insight) onOpen;

  @override
  State<InsightDeck> createState() => _InsightDeckState();
}

class _InsightDeckState extends State<InsightDeck> {
  /// Tall enough for the worst case the copy allows: a two-line title, three
  /// lines of body and an action. Measured, not guessed — a shorter card
  /// silently truncates the longest suggestion, which is usually the one that
  /// matters most.
  static const _height = 196.0;

  /// How much of the next card shows past the right edge of the screen.
  static const _peek = 52.0;

  PageController? _pages;
  double? _builtFor;
  int _current = 0;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// The controller depends on the screen width, which is not known until the
  /// first layout — so it is built here rather than in initState, and rebuilt
  /// only if the width actually changes (a rotation, a foldable).
  PageController _controllerFor(double screen) {
    if (_pages != null && _builtFor == screen) return _pages!;
    _pages?.dispose();
    _builtFor = screen;
    return _pages = PageController(
      viewportFraction: _fractionFor(screen),
      initialPage: _current,
    );
  }

  /// The viewport starts after the screen's left gutter and runs to the right
  /// edge, so a card is `screen − gutter − peek` wide and the next one is
  /// [_peek] past the edge.
  static double _fractionFor(double screen) {
    final viewport = screen - TackSpace.screen;
    final card = screen - TackSpace.screen - _peek;
    return ((card + TackSpace.stack) / viewport).clamp(0.1, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.insights.isEmpty) return const SizedBox.shrink();
    final insights = widget.insights;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.maxWidth;
        final controller = _controllerFor(screen);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: TackSpace.screen),
              child: SizedBox(
                height: _height,
                child: PageView.builder(
                  controller: controller,
                  padEnds: false,
                  itemCount: insights.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: TackSpace.stack),
                    child: _InsightCard(
                      insight: insights[i],
                      onOpen: () => widget.onOpen(insights[i]),
                    ),
                  ),
                ),
              ),
            ),
            if (insights.length > 1) ...[
              const SizedBox(height: TackSpace.md),
              Padding(
                padding: const EdgeInsets.only(left: TackSpace.screen),
                child: _Dots(count: insights.length, current: _current),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onOpen});

  final Insight insight;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final (background, accent) = switch (insight.tone) {
      // Every one of these foregrounds is the audited text colour for its
      // family, never the fill. #C9B6BC and the raw teal and amber are strokes.
      InsightTone.urgent => (TackColors.maroonTint, TackColors.maroon),
      InsightTone.positive => (TackColors.tealTint, TackColors.tealText),
      InsightTone.opportunity => (TackColors.amberTint, TackColors.amberText),
      InsightTone.neutral => (TackColors.white, TackColors.muted),
    };

    return Semantics(
      button: insight.route != null,
      label: '${insight.title}. ${insight.body}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: insight.route == null ? null : onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: TackSpace.cardCompactX,
            vertical: TackSpace.cardCompactY,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: TackRadius.cardAll,
            border: insight.tone == InsightTone.neutral
                ? Border.all(color: TackColors.line, width: 1)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.label,
                style: TackText.monoLabelSmall.copyWith(color: accent),
              ),
              const SizedBox(height: TackSpace.sm),
              Text(
                insight.title,
                style: TackText.cardTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: TackSpace.xs),
              // Flexible, not Expanded, and no Spacer beside it.
              //
              // Expanded forces the whole remaining height onto the Text, which
              // then paints three lines into a box that fits two and a half and
              // clips the last through the middle of the glyphs. Adding a
              // Spacer to pin the action to the bottom made it worse: both flex
              // children then split the space and the text got half of it.
              //
              // Flexible alone hands the Text a maximum and lets it take only
              // what it needs, so it ellipsises honestly and the action sits
              // directly under it.
              Flexible(
                child: Text(
                  insight.body,
                  style: TackText.bodyMuted,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (insight.ctaLabel != null) ...[
                const SizedBox(height: TackSpace.sm),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        insight.ctaLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TackText.pill.copyWith(
                          color: accent,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: TackSpace.xs),
                    TackIcon(TackIcons.arrowRight, size: 15, color: accent),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Page dots. The active one widens rather than changing size, so the row
/// never reflows and the animation is a width tween and nothing else.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Suggestion ${current + 1} of $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedContainer(
              duration: TackMotion.normal,
              curve: TackMotion.curve,
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == current ? TackColors.maroon : TackColors.line2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
