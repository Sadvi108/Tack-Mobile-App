import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

import '../application/interview.dart';
import 'feedback_view.dart';

class QuestionView extends ConsumerStatefulWidget {
  const QuestionView({
    super.key,
    required this.session,
    required this.onAnswered,
    required this.onFinished,
  });

  final InterviewSession session;
  final ValueChanged<InterviewSession> onAnswered;
  final Future<void> Function(InterviewSession session) onFinished;

  @override
  ConsumerState<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends ConsumerState<QuestionView> {
  final _answer = TextEditingController();
  bool _busy = false;
  AnswerFeedback? _feedback;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  InterviewQuestion get _current =>
      widget.session.nextUnanswered ?? widget.session.questions.last;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final question = _current;
    final index = session.questions.indexOf(question);
    final feedback = _feedback;

    if (feedback != null) {
      return FeedbackView(
        feedback: feedback,
        questionNumber: index + 1,
        total: session.questions.length,
        isLast: index == session.questions.length - 1,
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
        children: [
          TackButton(
            'Submit answer',
            loading: _busy,
            onPressed: _answer.text.trim().length >= 20 ? _submit : null,
          ),
          const SizedBox(height: TackSpace.sm),
          TackButton.ghost('Skip this one', onPressed: _busy ? null : _skip),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            _answer.text.trim().length < 20
                ? 'Write a little more and the feedback will be useful.'
                : '${_answer.text.trim().split(RegExp(r"\s+")).length} words',
            style: TackText.meta.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: TackSpace.md),
          Text(
            'Submitting uses one AI action for feedback. Skipping uses none.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
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
