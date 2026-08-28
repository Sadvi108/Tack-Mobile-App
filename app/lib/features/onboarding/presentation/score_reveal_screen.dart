import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/profile.dart';

/// The first thing a student sees after finishing.
///
/// The number will be low, and that is the point: it is a starting position,
/// not a grade, and the screen says so before the student has time to read it
/// as a verdict.
class ScoreRevealScreen extends ConsumerWidget {
  const ScoreRevealScreen({super.key, required this.score, required this.mode});

  final int score;
  final YearMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TackScaffold(
      pinnedCta: TackButton(
        'See what raises it',
        onPressed: () => context.go(Routes.home),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: TackSpace.xl),
          Text('You are set up', style: TackText.screenTitle),
          const SizedBox(height: TackSpace.sm),
          Text(
            'Here is where you are starting from.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.xl),

          Center(
            child: ScoreRing(score: score, size: 148, caption: 'of 100'),
          ),
          const SizedBox(height: TackSpace.xl),

          TackCard(
            emphasised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This is a starting point', style: TackText.cardTitle),
                const SizedBox(height: TackSpace.sm),
                Text(
                  'Everyone begins low, including the people who end up with '
                  'good jobs. It moves fastest at the start, and the app will '
                  'always tell you which single thing moves it most.',
                  style: TackText.bodyMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          TackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WHAT TACK WILL DO NOW', style: TackText.monoLabel),
                const SizedBox(height: TackSpace.md),
                Text(_explain(mode), style: TackText.body),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }

  /// What the app is actually for, in the words of the mode they landed in.
  static String _explain(YearMode mode) => switch (mode) {
    YearMode.discover =>
      'Help you work out what you are good at and what to study, without '
          'saying a word about job applications.',
    YearMode.explore =>
      'Help you try things and find a direction, before any of it matters.',
    YearMode.build => 'Help you build real skills and your first project.',
    YearMode.prove =>
      'Help you get an internship, build a portfolio and meet people.',
    YearMode.launch =>
      'Help you apply, keep track of every application, and practise for '
          'interviews.',
    YearMode.graduate =>
      'Help you apply, keep track of every application, and practise for '
          'interviews.',
  };
}
