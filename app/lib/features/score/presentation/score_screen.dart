import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/readiness.dart';
import '../data/score_repository.dart';
import 'trend_chart.dart';

/// The readiness score in detail.
///
/// The screen answers two questions in order: why is it this number, and what
/// raises it fastest. Rows are sorted by points still available, so the
/// biggest win is first and the pinned action matches row one.
class ScoreScreen extends ConsumerWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreAsync = ref.watch(readinessProvider);
    final trend =
        ref.watch(scoreTrendProvider).value ?? const <ReadinessScore>[];
    final cohort = ref.watch(cohortProvider).value;
    final mode = ref.watch(modeProvider);
    final weekChange = ref.watch(weekChangeProvider).value ?? 0;

    return scoreAsync.when(
      loading: () => TackScaffold(
        header: TackHeader(
          title: 'Readiness score',
          onBack: () => context.go(Routes.home),
        ),
        body: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TackSkeleton(height: 150, radius: 20),
            SizedBox(height: TackSpace.stackLoose),
            TackSkeleton(height: 240, radius: 20),
          ],
        ),
      ),
      error: (_, _) => TackScaffold(
        header: TackHeader(
          title: 'Readiness score',
          onBack: () => context.go(Routes.home),
        ),
        body: TackErrorState(
          body: 'Your score did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(readinessProvider),
        ),
      ),
      data: (score) {
        final rows = score.byOpportunity;
        final biggestWin = score.opportunities.firstOrNull;
        final dormant = score.notCountedThisYear;

        return TackScaffold(
          header: TackHeader(
            title: 'Readiness score',
            onBack: () => context.go(Routes.home),
          ),
          pinnedCta: biggestWin == null
              ? null
              : TackButton(
                  biggestWin.action,
                  onPressed: () => context.go(biggestWin.route),
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TackCard(
                child: Row(
                  children: [
                    ScoreRing(score: score.total, caption: 'of 100'),
                    const SizedBox(width: TackSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                            ),
                          const SizedBox(height: TackSpace.xs),
                          Text(
                            _framing(score.total, cohort, mode),
                            style: TackText.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              TackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAST 90 DAYS', style: TackText.monoLabel),
                    const SizedBox(height: TackSpace.md),
                    ScoreTrendChart(history: trend),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              Text('What makes it up', style: TackText.sectionHeader),
              const SizedBox(height: TackSpace.sm),
              Text(
                'Eleven parts, weighted for ${_yearPhrase(mode)}. The biggest win is first.',
                style: TackText.bodyMuted,
              ),
              const SizedBox(height: TackSpace.md),

              TackCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.cardX,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const TackDivider(),
                      _ComponentRow(
                        component: rows[i],
                        onTap: () => context.go(rows[i].route),
                      ),
                    ],
                  ],
                ),
              ),

              if (dormant.isNotEmpty) ...[
                const SizedBox(height: TackSpace.stackLoose),
                TackCard(
                  background: TackColors.amberTint,
                  compact: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not counted in your year',
                        style: TackText.cardTitle,
                      ),
                      const SizedBox(height: TackSpace.xs),
                      Text(
                        '${_list(dormant.map((c) => c.label.toLowerCase()))} '
                        '${dormant.length == 1 ? 'does' : 'do'} not affect your score yet. '
                        'That is deliberate — it starts counting in a later year.',
                        style: TackText.bodyMuted,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }

  static String _yearPhrase(YearMode mode) => switch (mode) {
    YearMode.discover => 'someone still at school',
    YearMode.graduate => 'a recent graduate',
    YearMode.explore => 'a first-year',
    YearMode.build => 'a second-year',
    YearMode.prove => 'a third-year',
    YearMode.launch => 'a final-year',
  };

  static String _framing(int score, CohortBenchmark? cohort, YearMode mode) {
    if (cohort == null) {
      return score == 0
          ? 'Everyone starts here. The first few steps move it fastest.'
          : 'Compared against your own year, never against final-years.';
    }
    final noun = mode.cohortNoun;
    if (score >= cohort.average + 5) return 'Ahead of most $noun.';
    if (score >= cohort.average - 5) return 'About average for $noun.';
    return 'A little behind most $noun, and very fixable.';
  }

  static String _list(Iterable<String> items) {
    final list = items.toList();
    if (list.length == 1) return list.single;
    return '${list.take(list.length - 1).join(', ')} and ${list.last}';
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component, required this.onTap});

  final ScoreComponent component;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TackTapRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(component.label, style: TackText.rowTitle)),
              Text(
                '${component.earned} of ${component.max}',
                style: TackText.meta.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.sm),
          TackProgressBar.health(value: component.ratio),
          if (component.available > 0) ...[
            const SizedBox(height: TackSpace.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    component.action,
                    style: TackText.meta.copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(width: TackSpace.sm),
                TackPill('+${component.available}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
