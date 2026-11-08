import 'package:flutter/material.dart';
import 'package:tack/design/tack.dart';

import '../application/interview.dart';
import 'interview_widgets.dart';

/// The free check: the student ticks which key points their answer covered.
///
/// No model, no AI action. Leaving saves once, through [onNext] or
/// [onAiFeedback]; the screen that owns this view does the save and shows any
/// failure, and this view keeps the answer and the ticks on screen until it
/// succeeds.
class SelfCheckView extends StatefulWidget {
  const SelfCheckView({
    super.key,
    required this.question,
    required this.answer,
    required this.questionNumber,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onAiFeedback,
    required this.onBack,
    this.busy = false,
    this.canAskAi = true,
  });

  /// AI feedback needs an answer of a few sentences; shorter ones can still
  /// be checked here.
  final bool canAskAi;

  final InterviewQuestion question;
  final String answer;
  final int questionNumber;
  final int total;
  final bool isLast;
  final bool busy;

  /// Saves the check and moves on. [covered] holds the ticked indexes.
  final ValueChanged<List<int>> onNext;

  /// Saves the check, then asks for AI feedback on the same answer.
  final ValueChanged<List<int>> onAiFeedback;

  /// Back to the answer, ticks kept.
  final VoidCallback onBack;

  @override
  State<SelfCheckView> createState() => _SelfCheckViewState();
}

class _SelfCheckViewState extends State<SelfCheckView> {
  final _covered = <int>{};
  bool _showAnswer = false;

  List<int> get _sorted => _covered.toList()..sort();

  @override
  Widget build(BuildContext context) {
    final points = widget.question.keyPoints;

    return TackScaffold(
      header: TackHeader(
        title: 'Question ${widget.questionNumber} of ${widget.total}',
        onBack: widget.onBack,
        progress: SegmentedProgress(
          total: widget.total,
          current: widget.questionNumber,
        ),
      ),
      pinnedCta: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TackButton(
            widget.isLast ? 'See your summary' : 'Next question',
            loading: widget.busy,
            onPressed: widget.busy ? null : () => widget.onNext(_sorted),
          ),
          const SizedBox(height: TackSpace.sm),
          TackButton.secondary(
            'Get AI feedback too',
            onPressed: widget.busy || !widget.canAskAi
                ? null
                : () => widget.onAiFeedback(_sorted),
          ),
          const SizedBox(height: TackSpace.xs),
          Text(
            widget.canAskAi
                ? 'Uses one AI action.'
                : 'Uses one AI action. Write a little more to ask for it.',
            style: TackText.meta,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackCard(
            child: Text(widget.question.question, style: TackText.cardTitle),
          ),
          const SizedBox(height: TackSpace.stack),
          TackCard(
            compact: true,
            onTap: () => setState(() => _showAnswer = !_showAnswer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('What you said', style: TackText.rowTitle),
                    ),
                    TackIcon(
                      _showAnswer ? TackIcons.chevronUp : TackIcons.chevronDown,
                      size: 20,
                      color: TackColors.muted,
                    ),
                  ],
                ),
                if (_showAnswer) ...[
                  const SizedBox(height: TackSpace.sm),
                  Text(widget.answer, style: TackText.body),
                ],
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),
          Text('A strong answer covers', style: TackText.sectionHeader),
          const SizedBox(height: TackSpace.xs),
          Text('Tick each one your answer covered.', style: TackText.bodyMuted),
          const SizedBox(height: TackSpace.sm),
          for (var i = 0; i < points.length; i++)
            KeyPointCheckRow(
              point: points[i],
              checked: _covered.contains(i),
              onChanged: (on) =>
                  setState(() => on ? _covered.add(i) : _covered.remove(i)),
            ),
          const SizedBox(height: TackSpace.md),
          Text(
            coverageLine(_covered.length, points.length),
            style: TackText.rowTitle,
          ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}
