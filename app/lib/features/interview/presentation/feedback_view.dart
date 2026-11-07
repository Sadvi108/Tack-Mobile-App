import 'package:flutter/material.dart';
import 'package:tack/design/tack.dart';

import '../application/interview.dart';
import 'interview_widgets.dart';

class FeedbackView extends StatefulWidget {
  const FeedbackView({
    super.key,
    required this.feedback,
    required this.questionNumber,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onFinish,
  });

  final AnswerFeedback feedback;
  final int questionNumber;
  final int total;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  @override
  State<FeedbackView> createState() => _FeedbackViewState();
}

class _FeedbackViewState extends State<FeedbackView> {
  bool _showModel = false;

  @override
  Widget build(BuildContext context) {
    final feedback = widget.feedback;

    return TackScaffold(
      header: TackHeader(title: 'Feedback'),
      pinnedCta: TackButton(
        widget.isLast ? 'See your summary' : 'Next question',
        onPressed: widget.isLast ? widget.onFinish : widget.onNext,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackCard(
            child: Row(
              children: [
                ScoreRing(
                  score: feedback.score.round(),
                  max: 10,
                  size: 84,
                  strokeWidth: 9,
                  caption: 'of 10',
                ),
                const SizedBox(width: TackSpace.lg),
                Expanded(
                  child: Text(
                    feedback.score >= 7
                        ? 'A strong answer.'
                        : feedback.score >= 5
                        ? 'A solid answer with room to sharpen it.'
                        : 'A start. The notes below are the fastest way to improve it.',
                    style: TackText.bodyMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          // What went well always comes first.
          if (feedback.wentWell.isNotEmpty) ...[
            PointsCard(
              title: 'What went well',
              items: feedback.wentWell,
              background: TackColors.tealTint,
              icon: TackIcons.check,
              iconColor: TackColors.tealText,
            ),
            const SizedBox(height: TackSpace.stack),
          ],
          if (feedback.toImprove.isNotEmpty) ...[
            PointsCard(
              title: 'What to sharpen',
              items: feedback.toImprove,
              background: TackColors.amberTint,
              icon: TackIcons.arrowRight,
              iconColor: TackColors.amberText,
            ),
            const SizedBox(height: TackSpace.stack),
          ],

          if (feedback.modelAnswer != null)
            TackCard(
              onTap: () => setState(() => _showModel = !_showModel),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'One way to answer it',
                          style: TackText.cardTitle,
                        ),
                      ),
                      TackIcon(
                        _showModel
                            ? TackIcons.chevronUp
                            : TackIcons.chevronDown,
                        size: 20,
                        color: TackColors.muted,
                      ),
                    ],
                  ),
                  if (_showModel) ...[
                    const SizedBox(height: TackSpace.md),
                    Text(feedback.modelAnswer!, style: TackText.body),
                  ],
                ],
              ),
            ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}
