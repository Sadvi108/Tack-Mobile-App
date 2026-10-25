import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tack.dart';
import '../../profile/data/profile.dart';
import '../application/next_actions.dart';
import 'motion.dart';

/// The chip above the greeting. It warms from amber to maroon as the years
/// progress, so the app visibly changes character alongside the student.
class ModeChip extends StatelessWidget {
  const ModeChip(this.mode, {super.key});

  final YearMode mode;

  @override
  Widget build(BuildContext context) {
    // The chip warms from amber to maroon as a student gets closer to working.
    final (background, foreground) = switch (mode) {
      YearMode.discover => (TackColors.amberTint, TackColors.amberText),
      YearMode.graduate => (TackColors.maroonTint, TackColors.maroonText),
      YearMode.explore => (TackColors.amberTint, TackColors.amberText),
      YearMode.build => (TackColors.tealTint, TackColors.tealText),
      YearMode.prove => (TackColors.tealDeepTint, TackColors.tealText),
      YearMode.launch => (TackColors.maroonTint, TackColors.maroonText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: TackRadius.pillAll,
      ),
      child: Text(
        mode.chipText,
        style: TackText.pill.copyWith(color: foreground),
      ),
    );
  }
}

/// The single most important element on the dashboard.
///
/// Emphasised with a maroon border rather than a shadow, and every row names
/// its point value so the score and the to-do list explain each other.
class NextThreeActions extends StatelessWidget {
  const NextThreeActions({
    super.key,
    required this.actions,
    required this.onOpen,
    this.onTickTask,
    this.heading = 'Your next three actions',
  });

  final List<NextAction> actions;
  final void Function(NextAction action) onOpen;
  final void Function(NextAction action)? onTickTask;
  final String heading;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return TackCard(
        emphasised: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: TackText.cardTitle),
            const SizedBox(height: TackSpace.sm),
            Text(
              'Nothing waiting right now. Pick a career path and Tack will build the next steps.',
              style: TackText.bodyMuted,
            ),
          ],
        ),
      );
    }

    return TackCard(
      emphasised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const TackDivider(),
            _ActionRow(
              action: actions[i],
              onOpen: () => onOpen(actions[i]),
              onTick: actions[i].isTask && onTickTask != null
                  ? () => onTickTask!(actions[i])
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.action, required this.onOpen, this.onTick});

  final NextAction action;
  final VoidCallback onOpen;
  final VoidCallback? onTick;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  /// Ticked here, before the write lands. The row leaves the list once the
  /// feed reloads, and a box that stays empty for that second reads as a tap
  /// that did not register — so the student taps again.
  bool _ticked = false;

  @override
  void didUpdateWidget(_ActionRow old) {
    super.didUpdateWidget(old);
    // A different action has moved into this slot; it has not been ticked.
    if (old.action.taskId != widget.action.taskId ||
        old.action.title != widget.action.title) {
      _ticked = false;
    }
  }

  void _tick() {
    if (_ticked) return;
    HapticFeedback.lightImpact();
    setState(() => _ticked = true);
    widget.onTick!();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;

    return TackTapRow(
      onTap: widget.onOpen,
      padding: const EdgeInsets.symmetric(vertical: TackSpace.sm),
      child: Row(
        children: [
          // A roadmap step can be ticked where it is. Anything else is a thing
          // to add to the profile, and an empty checkbox that does nothing
          // when pressed is a small lie — so it gets a plus instead.
          if (widget.onTick != null)
            _TickBox(ticked: _ticked, title: action.title, onTick: _tick)
          else
            const _AddMark(),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: TackMotion.normal,
              curve: TackMotion.curve,
              style: _ticked
                  ? TackText.rowTitle.copyWith(
                      color: TackColors.muted,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: TackColors.muted,
                    )
                  : TackText.rowTitle,
              child: Text(action.title),
            ),
          ),
          const SizedBox(width: TackSpace.sm),
          TackPill.teal('+${action.points}'),
        ],
      ),
    );
  }
}

/// The checkbox, with a hit area four times the size of the box. A 22px target
/// beside a row that also opens something means every near-miss navigates
/// away instead of ticking.
class _TickBox extends StatelessWidget {
  const _TickBox({
    required this.ticked,
    required this.title,
    required this.onTick,
  });

  final bool ticked;
  final String title;
  final VoidCallback onTick;

  @override
  Widget build(BuildContext context) {
    // Its own node. Without container it merges into the row around it, and
    // a screen reader hears one button that opens the step — never one that
    // ticks it.
    return Semantics(
      container: true,
      button: true,
      checked: ticked,
      label: 'Mark $title as done',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTick,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: TackSpace.tapTarget,
          height: TackSpace.tapTarget,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: TackMotion.normal,
              curve: TackMotion.curve,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: ticked ? TackColors.teal : TackColors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: ticked ? TackColors.teal : TackColors.strokeFaint,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: ticked ? 1 : 0,
                duration: TackMotion.normal,
                curve: Curves.easeOutBack,
                child: TackIcon(
                  TackIcons.check,
                  size: 14,
                  strokeWidth: 3,
                  color: TackColors.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMark extends StatelessWidget {
  const _AddMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TackSpace.tapTarget,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TackColors.maroonTint,
            borderRadius: BorderRadius.circular(7),
          ),
          child: TackIcon(
            TackIcons.plus,
            size: 14,
            strokeWidth: 2.6,
            color: TackColors.maroonText,
          ),
        ),
      ),
    );
  }
}

/// The four-cell funnel. Only ever rendered in launch mode.
class ApplicationFunnel extends StatelessWidget {
  const ApplicationFunnel({super.key, required this.counts, this.onTap});

  /// Keyed by status name: applied, assessment, interview, offer.
  final Map<String, int> counts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const stages = [
      TackStatus.applied,
      TackStatus.assessment,
      TackStatus.interview,
      TackStatus.offer,
    ];

    return TackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your applications', style: TackText.cardTitle),
              ),
              if (onTap != null) const TackCardArrow(),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          // Two by two, not four across. A quarter of a 360px card is too
          // narrow for "Assessment" at a readable size, and a label scaled
          // down to fit was eight pixels tall.
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: TackSpace.sm),
            Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: TackSpace.sm),
                  Expanded(
                    child: _Stage(
                      status: stages[row * 2 + col],
                      count: counts[stages[row * 2 + col].wire] ?? 0,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One stage of the funnel, tinted the way its status pill is everywhere else
/// in the app — so "interview" is the same amber here as on the card it opens.
///
/// A stage with nothing in it goes neutral. The zero is still printed, so the
/// colour is never the only thing saying so.
class _Stage extends StatelessWidget {
  const _Stage({required this.status, required this.count});

  final TackStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final empty = count == 0;
    final background = empty ? TackColors.sailWhite : status.background;
    final foreground = empty ? TackColors.muted : status.foreground;

    return Semantics(
      label: '$count ${status.label.toLowerCase()}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TackSpace.md,
          vertical: TackSpace.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TackCountUp(
              count,
              style: TackText.heroNumber.copyWith(
                fontSize: 26,
                color: foreground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TackText.pill.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A plain section heading with an optional "see all" affordance.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.md),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TackText.sectionHeader)),
          if (actionLabel != null)
            TackPressable(
              onTap: onAction,
              scale: 1,
              pressedOpacity: 0.55,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: TackSpace.tapTarget,
                ),
                child: Center(
                  child: Text(
                    actionLabel!,
                    style: TackText.pill.copyWith(
                      color: TackColors.maroonText,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The readiness figure, and what it is made of.
///
/// The sentence underneath is the point: a number on its own is a verdict, and
/// "two of nine areas have any score" is a to-do list. The fraction only ever
/// counts areas that carry weight in this student's mode — a component
/// weighted zero for them is a question nobody asked, not a failure.
class ReadinessBlock extends StatelessWidget {
  const ReadinessBlock({
    super.key,
    required this.score,
    required this.areasScored,
    required this.areasCounted,
    required this.onSeeBreakdown,
    this.animated = false,
  });

  final int score;
  final int areasScored;
  final int areasCounted;
  final VoidCallback onSeeBreakdown;

  /// Sweeps the ring to its value once, on the dashboard only. A number that
  /// climbs to 34 reads as something that moves; a number that is simply there
  /// reads as a verdict, and "your score moves" is the claim this app most
  /// needs a student to believe on day one.
  final bool animated;

  @override
  Widget build(BuildContext context) {
    // The whole card opens the breakdown, not only the link. The link is a
    // line of 16px text; the card is the thing a thumb actually lands on.
    return TackCard(
      onTap: onSeeBreakdown,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (animated)
            AnimatedScoreRing(score: score, size: 92)
          else
            ScoreRing(score: score, size: 92, caption: null),
          const SizedBox(width: TackSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('READINESS / 100', style: TackText.monoLabelSmall),
                const SizedBox(height: TackSpace.sm),
                Text(_sentence, style: TackText.body),
                const SizedBox(height: TackSpace.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    // Spelled out, as drawn: "See the nine" reads as a
                    // sentence where "See the 9" reads as a label.
                    'See the ${_word(areasCounted).toLowerCase()}  →',
                    style: TackText.rowTitle.copyWith(
                      color: TackColors.maroonText,
                      decoration: TextDecoration.underline,
                      decorationColor: TackColors.amber,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _sentence {
    if (areasCounted == 0) return 'Your score is still being worked out.';
    if (areasScored == 0) {
      return 'Nothing is scored yet. That is normal on day one.';
    }
    if (areasScored == areasCounted) return 'Every area has something in it.';
    return '${_word(areasScored)} of $areasCounted areas have any score.';
  }

  static String _word(int n) => switch (n) {
    1 => 'One',
    2 => 'Two',
    3 => 'Three',
    4 => 'Four',
    5 => 'Five',
    6 => 'Six',
    7 => 'Seven',
    8 => 'Eight',
    9 => 'Nine',
    _ => '$n',
  };
}

/// The first-run checklist.
///
/// Rows are computed from what the student is actually missing, so a step they
/// have finished disappears and the whole card goes once they are set up. The
/// point values come from the score engine rather than being written here,
/// which is what stops the card and the score disagreeing.
class StartHereCard extends StatelessWidget {
  const StartHereCard({super.key, required this.steps, required this.onOpen});

  final List<NextAction> steps;
  final void Function(NextAction step) onOpen;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    return TackCard(
      emphasised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DO THIS FIRST', style: TackText.monoLabelSmall),
          const SizedBox(height: TackSpace.md),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const TackDivider(),
            _StartHereRow(
              index: i + 1,
              step: steps[i],
              onTap: () => onOpen(steps[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartHereRow extends StatelessWidget {
  const _StartHereRow({
    required this.index,
    required this.step,
    required this.onTap,
  });

  final int index;
  final NextAction step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // "1 min · builds your roadmap" rather than "+0 points": a step worth no
    // points directly is not worth nothing, and saying so is more honest than
    // printing a zero.
    final worth = step.points > 0
        ? '${step.effortMinutes} min · +${step.points} points'
        : '${step.effortMinutes} min · builds your roadmap';

    return TackPressable(
      onTap: onTap,
      scale: 1,
      pressedOpacity: 0.55,
      semanticLabel: '${step.title}. $worth',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: TackText.monoLabel.copyWith(
                  color: index == 1 ? TackColors.maroonText : TackColors.muted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: TackText.rowTitle),
                  const SizedBox(height: 2),
                  Text(worth, style: TackText.meta),
                ],
              ),
            ),
            const SizedBox(width: TackSpace.sm),
            TackIcon(TackIcons.arrowRight, size: 18, color: TackColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Says out loud what a student worries about the moment they see a score.
///
/// A footnote, not a card: boxed in the page colour it sat on the glows as a
/// flat slab, the heaviest thing at the end of the screen for the lightest
/// message on it.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.xs,
        vertical: TackSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Sits on the first line's cap height rather than its top.
            padding: const EdgeInsets.only(top: 3),
            child: TackIcon(
              TackIcons.shield,
              size: 18,
              color: TackColors.muted,
            ),
          ),
          const SizedBox(width: TackSpace.sm),
          Expanded(
            child: Text(
              'Nothing here is public. Your score is only for you.',
              style: TackText.bodyMuted,
            ),
          ),
        ],
      ),
    );
  }
}
