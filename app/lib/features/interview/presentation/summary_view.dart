import 'package:flutter/material.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

import '../application/interview.dart';

class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.session, required this.onAgain});

  final InterviewSession session;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    // A free session is measured against its key points, never as a zero out
    // of ten: nothing was scored, so there is no score to show.
    final Widget? ring = session.anyAiScored
        ? ScoreRing(
            score: (session.overallScore ?? session.averageScore).round(),
            max: 10,
            caption: 'of 10',
          )
        : session.keyPointsTotal > 0
        ? ScoreRing(
            score: session.keyPointsCovered,
            max: session.keyPointsTotal,
            caption: 'key points covered',
          )
        : null;

    return TackScaffold(
      header: TackHeader(title: 'How it went', onBack: () => tackBack(context)),
      pinnedCta: TackButton('Practise again', onPressed: onAgain),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackCard(
            child: Row(
              children: [
                if (ring != null) ...[
                  ring,
                  const SizedBox(width: TackSpace.lg),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${session.role} practice',
                        style: TackText.cardTitle,
                      ),
                      const SizedBox(height: TackSpace.xs),
                      Text(
                        '${session.answeredCount} of ${session.questions.length} answered',
                        style: TackText.meta,
                      ),
                      if (session.pointsEarned > 0) ...[
                        const SizedBox(height: TackSpace.sm),
                        TackPill.teal('+${session.pointsEarned} points'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          if (session.strongestArea != null || session.weakestArea != null)
            TackCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (session.strongestArea != null) ...[
                    Text('Strongest', style: TackText.monoLabel),
                    const SizedBox(height: 4),
                    Text(
                      displayCategory(session.strongestArea!),
                      style: TackText.rowTitle,
                    ),
                    const SizedBox(height: TackSpace.md),
                  ],
                  if (session.weakestArea != null) ...[
                    Text('WORTH PRACTISING', style: TackText.monoLabel),
                    const SizedBox(height: 4),
                    Text(
                      displayCategory(session.weakestArea!),
                      style: TackText.rowTitle,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: TackSpace.stackLoose),

          Text('Your answers', style: TackText.sectionHeader),
          const SizedBox(height: TackSpace.md),
          for (final question in session.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: TackSpace.row),
              child: TackCard(
                compact: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        question.question,
                        style: TackText.rowTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: TackSpace.sm),
                    if (question.skipped)
                      TackPill(
                        'Skipped',
                        background: TackColors.line,
                        foreground: TackColors.muted,
                      )
                    else if (question.feedback != null)
                      TackPill.teal(question.feedback!.score.toStringAsFixed(1))
                    else if (question.selfCheck case final check?)
                      TackPill.teal(
                        '${check.covered.length} of ${check.total}',
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}
