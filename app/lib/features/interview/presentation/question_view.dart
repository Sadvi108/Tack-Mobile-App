import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

import '../application/interview.dart';
import 'feedback_view.dart';
import 'interview_widgets.dart';
import 'self_check_view.dart';

/// One question, answered in writing. A question from the pool can be checked
/// for free against its key points, with AI feedback as an extra; a company
/// pack or an older set has no key points and keeps the single submit.
class QuestionView extends ConsumerStatefulWidget {
  const QuestionView({
    super.key,
    required this.session,
    required this.onAnswered,
    required this.onFinished,
    this.packName,
  });

  final InterviewSession session;
  final ValueChanged<InterviewSession> onAnswered;
  final Future<void> Function(InterviewSession session) onFinished;

  /// Set when the session came from a company pack, which then says who wrote
  /// the questions.
  final String? packName;

  @override
  ConsumerState<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends ConsumerState<QuestionView> {
  final _answer = TextEditingController();
  bool _busy = false;
  bool _checking = false;
  AnswerFeedback? _feedback;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  InterviewQuestion get _current =>
      widget.session.nextUnanswered ?? widget.session.questions.last;

  bool get _longEnoughForAi => _answer.text.trim().length >= 20;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final question = _current;
    final index = session.questions.indexOf(question);
    final isLast = index == session.questions.length - 1;
    final feedback = _feedback;

    if (feedback != null) {
      return FeedbackView(
        feedback: feedback,
        keyPoints: question.keyPoints,
        questionNumber: index + 1,
        total: session.questions.length,
        isLast: isLast,
        onNext: () async {
          final refreshed = await ref
              .read(interviewRepositoryProvider)
              .byId(session.id);
          if (!mounted) return;
          setState(() {
            _feedback = null;
            _answer.clear();
          });
          if (refreshed != null) widget.onAnswered(refreshed);
        },
        onFinish: () async {
          final refreshed = await ref
              .read(interviewRepositoryProvider)
              .byId(session.id);
          await widget.onFinished(refreshed ?? session);
        },
      );
    }

    if (_checking) {
      return SelfCheckView(
        question: question,
        answer: _answer.text.trim(),
        questionNumber: index + 1,
        total: session.questions.length,
        isLast: isLast,
        busy: _busy,
        canAskAi: _longEnoughForAi,
        onBack: () => setState(() => _checking = false),
        onNext: _checkedNext,
        onAiFeedback: _checkedThenFeedback,
      );
    }

    final hasKeyPoints = question.keyPoints.isNotEmpty;
    return TackScaffold(
      header: TackHeader(
        title: 'Question ${index + 1} of ${session.questions.length}',
        onBack: () => tackBack(context),
        progress: SegmentedProgress(
          total: session.questions.length,
          current: index + 1,
        ),
      ),
      pinnedCta: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: hasKeyPoints
            ? [
                TackButton(
                  'Check against key points',
                  onPressed: _busy || _answer.text.trim().isEmpty
                      ? null
                      : () => setState(() => _checking = true),
                ),
                const SizedBox(height: TackSpace.sm),
                TackButton.secondary(
                  'Get AI feedback',
                  onPressed: _busy || !_longEnoughForAi ? null : _submit,
                ),
                const SizedBox(height: TackSpace.xs),
                TackButton.ghost(
                  'Skip this one',
                  onPressed: _busy ? null : _skip,
                ),
                Text(
                  'Checking is free. AI feedback uses one AI action.',
                  style: TackText.meta,
                  textAlign: TextAlign.center,
                ),
              ]
            : [
                TackButton(
                  'Submit answer',
                  loading: _busy,
                  onPressed: _longEnoughForAi ? _submit : null,
                ),
                const SizedBox(height: TackSpace.sm),
                TackButton.ghost(
                  'Skip this one',
                  onPressed: _busy ? null : _skip,
                ),
              ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.packName case final pack?) ...[
            PackDisclaimer(company: pack),
            const SizedBox(height: TackSpace.md),
          ],
          TackCard(
            child: Text(question.question, style: TackText.sectionHeader),
          ),
          const SizedBox(height: TackSpace.stackLoose),
          TackTextField(
            hint: 'Answer as you would out loud…',
            controller: _answer,
            maxLines: 10,
            minLines: 6,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            _longEnoughForAi
                ? '${_answer.text.trim().split(RegExp(r"\s+")).length} words'
                : 'Write a little more and the feedback will be useful.',
            style: TackText.meta,
          ),
          if (!hasKeyPoints) ...[
            const SizedBox(height: TackSpace.md),
            Text(
              'Submitting uses one AI action for feedback. Skipping uses none.',
              style: TackText.bodyMuted,
            ),
          ],
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }

  /// Saves the answer and its check. Shows the failure and returns false
  /// when it did not save; the answer and the ticks stay on screen.
  Future<bool> _saveCheck(List<int> covered) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(interviewRepositoryProvider)
          .saveOwnAnswer(
            questionId: _current.id,
            answer: _answer.text.trim(),
            covered: covered,
            total: _current.keyPoints.length,
          );
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        TackToast.show(
          context,
          message: Failure.from(e).message,
          kind: TackToastKind.error,
        );
      }
      return false;
    }
  }

  Future<void> _checkedNext(List<int> covered) async {
    if (!await _saveCheck(covered)) return;
    final refreshed = await ref
        .read(interviewRepositoryProvider)
        .byId(widget.session.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checking = false;
      _answer.clear();
    });
    final next = refreshed ?? widget.session;
    if (next.nextUnanswered == null) {
      await widget.onFinished(next);
    } else {
      widget.onAnswered(next);
    }
  }

  Future<void> _checkedThenFeedback(List<int> covered) async {
    if (!await _saveCheck(covered)) return;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checking = false;
    });
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final feedback = await ref
          .read(interviewRepositoryProvider)
          .submitAnswer(questionId: _current.id, answer: _answer.text);
      if (!mounted) return;
      setState(() {
        _feedback = feedback;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }

  Future<void> _skip() async {
    await ref.read(interviewRepositoryProvider).skip(_current.id);
    final refreshed = await ref
        .read(interviewRepositoryProvider)
        .byId(widget.session.id);
    if (!mounted || refreshed == null) return;
    _answer.clear();
    if (refreshed.nextUnanswered == null) {
      await widget.onFinished(refreshed);
    } else {
      widget.onAnswered(refreshed);
    }
  }
}
