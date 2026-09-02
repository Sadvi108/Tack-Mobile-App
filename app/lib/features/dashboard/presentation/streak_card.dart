import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/dashboard_feed.dart';
import 'motion.dart';

/// Showing up, drawn as fourteen squares.
///
/// This is the only figure on the dashboard that rewards turning up rather
/// than achieving something, which is exactly what carries a first-year
/// through a month where nothing scoreable happens.
///
/// It is deliberately not a game. There is no fire, no badge and no loss
/// message — a broken streak says the best run stands and today can start
/// another one, because a student who feels punished by a productivity app
/// stops opening it, and this one has to last four years.
class StreakCard extends StatelessWidget {
  const StreakCard({
    super.key,
    required this.streak,
    required this.today,
    this.days = 14,
  });

  final Streak streak;
  final DateTime today;
  final int days;

  @override
  Widget build(BuildContext context) {
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days - 1));

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SHOWING UP', style: TackText.monoLabelSmall),
                    const SizedBox(height: TackSpace.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        TackCountUp(
                          streak.current,
                          style: TackText.heroNumber.copyWith(fontSize: 30),
                          semanticsLabel: streak.current == 1
                              ? 'One day streak'
                              : '${streak.current} day streak',
                        ),
                        const SizedBox(width: TackSpace.sm),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            streak.current == 1 ? 'day' : 'days',
                            style: TackText.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (streak.isPersonalBest && streak.current >= 3)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: TackColors.tealTint,
                    borderRadius: TackRadius.pillAll,
                  ),
                  child: Text(
                    'Your best',
                    style: TackText.pill.copyWith(color: TackColors.tealText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          Semantics(
            label:
                'Active on ${streak.days.length} of the last $days days. '
                'Longest run ${streak.longest} days.',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 0; i < days; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _Day(
                      active: streak.wasActiveOn(start.add(Duration(days: i))),
                      isToday: i == days - 1,
                      index: i,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: TackSpace.md),
          Text(_sentence, style: TackText.bodyMuted),
        ],
      ),
    );
  }

  String get _sentence {
    if (streak.longest == 0) {
      return 'Every day you add something here fills a square. That is the whole game.';
    }
    if (streak.current == 0) {
      return 'Your longest run is ${streak.longest} days. Anything you add today starts the next one.';
    }
    if (streak.isPersonalBest) {
      return 'The longest you have kept going. Nothing to do but keep going.';
    }
    return 'Your longest run is ${streak.longest} days.';
  }
}

/// One square. Fades and lifts in as the row is laid down, then holds.
class _Day extends StatelessWidget {
  const _Day({
    required this.active,
    required this.isToday,
    required this.index,
  });

  final bool active;
  final bool isToday;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TackReveal(
      index: index,
      offset: 6,
      child: Container(
        height: 26,
        decoration: BoxDecoration(
          color: active ? TackColors.teal : TackColors.line,
          borderRadius: BorderRadius.circular(6),
          border: isToday && !active
              ? Border.all(color: TackColors.strokeFaint, width: 1.5)
              : null,
        ),
      ),
    );
  }
}
