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
    final (background, foreground) = switch (mode) {
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
