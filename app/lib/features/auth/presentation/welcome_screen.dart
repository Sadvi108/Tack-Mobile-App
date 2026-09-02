import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';

/// The first screen a signed-out student sees. One promise, one action.
///
/// The hero preview is real UI at a smaller scale rather than a screenshot, so
/// the screen stays light on a slow connection and never shows a stale image
/// of an older design.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TackScaffold(
      padBody: false,
      onMaroonHeader: true,
      background: TackColors.sailWhite,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: TackColors.maroon,
            padding: EdgeInsets.fromLTRB(
              TackSpace.screenWide,
              MediaQuery.paddingOf(context).top + TackSpace.lg,
              TackSpace.screenWide,
              30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TackWordmark(color: TackColors.amber),
                    GestureDetector(
                      onTap: () => context.go(Routes.login),
                      behavior: HitTestBehavior.opaque,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: TackSpace.tapTarget,
                        ),
                        child: Center(
                          child: Text(
                            'Log in',
                            style: TackText.rowTitle.copyWith(
                              color: const Color(0xCCFFFFFF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TackSpace.xl),
                Text(
                  'Your first job starts here',
                  style: TackText.landingH1.copyWith(color: TackColors.onBrand),
                ),
                const SizedBox(height: TackSpace.md),
                Text(
                  'Tack looks at where you are today and builds one personalised plan to get you '
                  'hired. Free for every student.',
                  style: TackText.bodyLarge.copyWith(
                    color: const Color(0xD1FFFFFF),
                  ),
                ),
                const SizedBox(height: TackSpace.xl),
                TackButton.amber(
                  'Start free',
                  onPressed: () => context.go(Routes.signup),
                ),
                const SizedBox(height: TackSpace.md),
                Center(
                  child: Text(
                    'No payment. No CV needed to begin.',
                    style: TackText.meta.copyWith(
                      color: const Color(0xA6FFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _HeroPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TackSpace.screenWide,
              TackSpace.xl,
              TackSpace.screenWide,
              TackSpace.xl,
            ),
            child: Column(
              children: [
                _FeatureRow(
                  icon: TackIcons.practice,
                  tint: TackColors.tealTint,
                  iconColor: TackColors.tealText,
                  title: 'Readiness score',
                  body:
                      'One number for how ready you are, and exactly what raises it.',
                ),
                SizedBox(height: TackSpace.md),
                _FeatureRow(
                  icon: TackIcons.roadmap,
                  tint: TackColors.maroonTint,
                  iconColor: TackColors.maroon,
                  title: 'Career roadmap',
                  body:
                      'A route from where you are to a job, broken into small steps.',
                ),
                SizedBox(height: TackSpace.md),
                _FeatureRow(
                  icon: TackIcons.apply,
                  tint: TackColors.amberTint,
                  iconColor: TackColors.amberText,
                  title: 'Application tracker',
                  body:
                      'Every job you applied to in one place, with what happens next.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A scaled-down render of the real dashboard, overlapping the hero seam.
class _HeroPreview extends StatelessWidget {
  const _HeroPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TackColors.maroon,
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Container(
        decoration: BoxDecoration(
          color: TackColors.sailWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Column(
          children: [
            Row(
              children: [
                const ScoreRing(
                  score: 61,
                  size: 54,
                  strokeWidth: 6,
                  caption: null,
                ),
                const SizedBox(width: TackSpace.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Readiness 61',
                      style: TackText.cardTitle.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+4 this week',
                      style: TackText.pill.copyWith(
                        color: TackColors.tealText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: TackSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              decoration: BoxDecoration(
                color: TackColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your next three actions',
                    style: TackText.cardTitle.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: TackSpace.sm),
                  const _PreviewAction(label: 'Upload your CV', points: '+9'),
                  const SizedBox(height: 7),
                  const _PreviewAction(label: 'Add three skills', points: '+6'),
                  const SizedBox(height: 7),
                  const _PreviewAction(
                    label: 'Practise one interview',
                    points: '+5',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewAction extends StatelessWidget {
  const _PreviewAction({required this.label, required this.points});

  final String label;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: TackColors.strokeFaint, width: 1.5),
          ),
        ),
        const SizedBox(width: TackSpace.sm),
        Expanded(
          child: Text(label, style: TackText.body.copyWith(fontSize: 12)),
        ),
        Text(
          points,
          style: TackText.pill.copyWith(
            color: TackColors.maroonText,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final String icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      compact: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: TackIcon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TackText.cardTitle),
                const SizedBox(height: TackSpace.xs),
                Text(body, style: TackText.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
