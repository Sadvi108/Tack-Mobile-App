import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../../profile/data/profile.dart';
import '../../score/data/score_repository.dart';
import '../application/next_actions.dart';

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
      YearMode.graduate => (TackColors.maroonTint, TackColors.maroon),
      YearMode.explore => (TackColors.amberTint, TackColors.amberText),
      YearMode.build => (TackColors.tealTint, TackColors.tealText),
      YearMode.prove => (TackColors.tealDeepTint, TackColors.tealText),
      YearMode.launch => (TackColors.maroonTint, TackColors.maroon),
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

/// The score card. Shows the week-on-week change, and the cohort comparison
/// against the student's own year — never against final-years.
class ScoreSummaryCard extends StatelessWidget {
  const ScoreSummaryCard({
    super.key,
    required this.score,
    required this.weekChange,
    required this.mode,
    this.cohort,
    this.onTap,
  });

  final int score;
  final int weekChange;
  final YearMode mode;
  final CohortBenchmark? cohort;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      onTap: onTap,
      child: Row(
        children: [
          ScoreRing(score: score, caption: 'of 100'),
          const SizedBox(width: TackSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Career readiness', style: TackText.cardTitle),
                const SizedBox(height: TackSpace.xs),
                if (weekChange != 0)
                  Text(
                    weekChange > 0
                        ? '+$weekChange this week'
                        : '$weekChange this week',
                    style: TackText.pill.copyWith(
                      color: weekChange > 0
                          ? TackColors.tealText
                          : TackColors.muted,
                    ),
                  )
                else
                  Text('No change this week', style: TackText.meta),
                const SizedBox(height: TackSpace.sm),
                Text(_framing, style: TackText.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The comparison, in words. A first-year on 30 reads as ahead, not behind,
  /// and the sentence says which year the comparison is against.
  String get _framing {
    final benchmark = cohort;
    if (benchmark == null) {
      return score == 0
          ? 'Everyone starts low. Three short steps will move it.'
          : 'This is a starting point, not a grade. It moves fast early.';
    }
    final noun = mode.cohortNoun;
    if (score >= benchmark.average + 5) return 'Ahead of most $noun.';
    if (score >= benchmark.average - 5) return 'About average for $noun.';
    return 'A little behind most $noun, and very fixable.';
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onOpen, this.onTick});

  final NextAction action;
  final VoidCallback onOpen;
  final VoidCallback? onTick;

  @override
  Widget build(BuildContext context) {
    return TackTapRow(
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTick,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TackColors.strokeFaint, width: 1.5),
              ),
            ),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(child: Text(action.title, style: TackText.rowTitle)),
          const SizedBox(width: TackSpace.sm),
          TackPill('+${action.points}'),
        ],
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
    const cells = [
      ('applied', 'Applied'),
      ('assessment', 'Assessment'),
      ('interview', 'Interview'),
      ('offer', 'Offer'),
    ];

    return TackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your applications', style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          Row(
            children: [
              for (final (key, label) in cells)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${counts[key] ?? 0}',
                        style: TackText.heroNumber.copyWith(fontSize: 27),
                      ),
                      const SizedBox(height: TackSpace.xs),
                      Text(
                        label,
                        style: TackText.tabLabel,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
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
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: TackSpace.tapTarget,
                ),
                child: Center(
                  child: Text(
                    actionLabel!,
                    style: TackText.pill.copyWith(
                      color: TackColors.maroon,
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
  });

  final int score;
  final int areasScored;
  final int areasCounted;
  final VoidCallback onSeeBreakdown;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
                Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: onSeeBreakdown,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        // Spelled out, as drawn: "See the nine" reads as a
                        // sentence where "See the 9" reads as a label.
                        'See the ${_word(areasCounted).toLowerCase()}  →',
                        style: TackText.rowTitle.copyWith(
                          color: TackColors.maroon,
                          decoration: TextDecoration.underline,
                          decorationColor: TackColors.amber,
                          decorationThickness: 2,
                        ),
                      ),
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

    return Semantics(
      button: true,
      label: '${step.title}. $worth',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: TackText.monoLabel.copyWith(
                    color: index == 1 ? TackColors.maroon : TackColors.muted,
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
              const TackIcon(
                TackIcons.arrowRight,
                size: 18,
                color: TackColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Says out loud what a student worries about the moment they see a score.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.cardCompactX,
        vertical: TackSpace.cardCompactY,
      ),
      decoration: const BoxDecoration(
        color: TackColors.sailWhite,
        borderRadius: BorderRadius.all(TackRadius.listCard),
      ),
      child: Text(
        'Nothing here is public. Your score is only for you.',
        style: TackText.bodyMuted,
      ),
    );
  }
}
