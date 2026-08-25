import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../profile/data/profile_repository.dart';
import '../../score/data/score_repository.dart';
import '../data/interview_models.dart';
import '../data/interview_repository.dart';

/// Interview practice.
///
/// One question per screen, the counter always visible, and the timer off by
/// default — a countdown is the fastest way to make an anxious first-timer
/// quit, so it has to be something they choose.
class InterviewScreen extends ConsumerStatefulWidget {
  const InterviewScreen({super.key});

  @override
  ConsumerState<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends ConsumerState<InterviewScreen> {
  InterviewSession? _session;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = _session;

    if (session == null) {
      return _Setup(
        busy: _busy,
        onStart: _start,
      );
    }
    if (session.isComplete) {
      return _Summary(
        session: session,
        onAgain: () => setState(() => _session = null),
      );
    }
    return _Question(
      session: session,
      onAnswered: (updated) => setState(() => _session = updated),
      onFinished: _complete,
    );
  }

  Future<void> _start({
    required String role,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timer,
  }) async {
    setState(() => _busy = true);
    try {
      final session = await ref.read(interviewRepositoryProvider).start(
            role: role,
            type: type,
            difficulty: difficulty,
            timerEnabled: timer,
          );
      if (!mounted) return;
      setState(() {
        _session = session;
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

  Future<void> _complete(InterviewSession session) async {
    try {
      final done = await ref.read(interviewRepositoryProvider).complete(session);
      ref
        ..invalidate(interviewHistoryProvider)
        ..invalidate(readinessProvider);
      if (!mounted) return;
      setState(() => _session = done);
    } catch (e) {
      if (!mounted) return;
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }
}

class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.busy, required this.onStart});

  final bool busy;
  final void Function({
    required String role,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timer,
  }) onStart;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  late String _role = ref.read(profileProvider).value?.targetRole ?? 'Frontend developer';
  InterviewType _type = InterviewType.mixed;
  Difficulty _difficulty = Difficulty.medium;

  /// Off by default, on purpose.
  bool _timer = false;

  static const _roles = [
    'Frontend developer',
    'Backend developer',
    'Data analyst',
    'Digital marketer',
    'HR executive',
    'Business analyst',
    'Graphic designer',
    'QA engineer',
    'Accountant',
    'Content writer',
  ];

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(interviewHistoryProvider).value ?? const <InterviewSession>[];

    return TackScaffold(
      header: TackHeader(title: 'Interview practice', onBack: () => context.pop()),
      pinnedCta: TackButton(
        'Start practising',
        loading: widget.busy,
        onPressed: () => widget.onStart(
          role: _role,
          type: _type,
          difficulty: _difficulty,
          timer: _timer,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Which role?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          TackSelectField<String>(
            hint: 'Choose a role',
            value: _role,
            valueLabel: (r) => r,
            onTap: () async {
              final picked = await showTackSheet<String>(
                context: context,
                title: 'Practise for',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final role in _roles)
                      TackTapRow(
                        onTap: () => Navigator.of(context).pop(role),
                        padding: const EdgeInsets.symmetric(
                          horizontal: TackSpace.screen,
                          vertical: 14,
                        ),
                        child: Text(role, style: TackText.rowTitle),
                      ),
                    const SizedBox(height: TackSpace.lg),
                  ],
                ),
              );
              if (picked != null) setState(() => _role = picked);
            },
          ),
          const SizedBox(height: TackSpace.lg),

          Text('What kind of questions?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final type in InterviewType.values)
                TackChip(
                  type.label,
                  selected: _type == type,
                  onTap: () => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.lg),

          Text('How hard?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final difficulty in Difficulty.values)
                TackChip(
                  difficulty.label,
                  selected: _difficulty == difficulty,
                  onTap: () => setState(() => _difficulty = difficulty),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.lg),

          TackCard(
            compact: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timed answers', style: TackText.rowTitle),
                      const SizedBox(height: 2),
                      Text(
                        'Off by default. Turn it on when you already feel ready.',
                        style: TackText.meta,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _timer,
                  activeThumbColor: TackColors.maroon,
                  onChanged: (v) => setState(() => _timer = v),
                ),
              ],
            ),
          ),

          if (history.isNotEmpty) ...[
            const SizedBox(height: TackSpace.xl),
            Text('Before', style: TackText.sectionHeader),
            const SizedBox(height: TackSpace.md),
            for (final past in history.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: TackSpace.row),
                child: TackCard(
                  compact: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(past.role, style: TackText.rowTitle),
                            const SizedBox(height: 2),
                            Text(
                              '${past.answeredCount} questions',
                              style: TackText.meta,
                            ),
                          ],
                        ),
                      ),
                      if (past.overallScore != null)
                        TackPill.teal('${past.overallScore!.toStringAsFixed(1)}/10'),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}

class _Question extends ConsumerStatefulWidget {
  const _Question({
    required this.session,
    required this.onAnswered,
    required this.onFinished,
  });

  final InterviewSession session;
  final ValueChanged<InterviewSession> onAnswered;
  final Future<void> Function(InterviewSession session) onFinished;

  @override
  ConsumerState<_Question> createState() => _QuestionState();
}

class _QuestionState extends ConsumerState<_Question> {
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
      return _Feedback(
        feedback: feedback,
        questionNumber: index + 1,
        total: session.questions.length,
        isLast: index == session.questions.length - 1,
        onNext: () async {
          final refreshed =
              await ref.read(interviewRepositoryProvider).byId(session.id);
          if (!mounted) return;
          setState(() {
            _feedback = null;
            _answer.clear();
          });
          if (refreshed != null) widget.onAnswered(refreshed);
        },
        onFinish: () async {
          final refreshed =
              await ref.read(interviewRepositoryProvider).byId(session.id);
          await widget.onFinished(refreshed ?? session);
        },
      );
    }

    return TackScaffold(
      header: TackHeader(
        title: 'Question ${index + 1} of ${session.questions.length}',
        onBack: () => context.pop(),
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
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final feedback = await ref.read(interviewRepositoryProvider).submitAnswer(
            questionId: _current.id,
            answer: _answer.text,
          );
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
    final refreshed = await ref.read(interviewRepositoryProvider).byId(widget.session.id);
    if (!mounted || refreshed == null) return;
    _answer.clear();
    if (refreshed.nextUnanswered == null) {
      await widget.onFinished(refreshed);
    } else {
      widget.onAnswered(refreshed);
    }
  }
}

class _Feedback extends StatefulWidget {
  const _Feedback({
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
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
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
            _Points(
              title: 'What went well',
              items: feedback.wentWell,
              background: TackColors.tealTint,
              icon: TackIcons.check,
              iconColor: TackColors.tealText,
            ),
            const SizedBox(height: TackSpace.stack),
          ],
          if (feedback.toImprove.isNotEmpty) ...[
            _Points(
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
                        child: Text('One way to answer it', style: TackText.cardTitle),
                      ),
                      TackIcon(
                        _showModel ? TackIcons.chevronUp : TackIcons.chevronDown,
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

class _Points extends StatelessWidget {
  const _Points({
    required this.title,
    required this.items,
    required this.background,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final List<String> items;
  final Color background;
  final String icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: TackSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: TackIcon(icon, size: 17, color: iconColor),
                  ),
                  const SizedBox(width: TackSpace.sm),
                  Expanded(child: Text(item, style: TackText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.session, required this.onAgain});

  final InterviewSession session;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    return TackScaffold(
      header: TackHeader(title: 'How it went', onBack: () => context.pop()),
      pinnedCta: TackButton('Practise again', onPressed: onAgain),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackCard(
            child: Row(
              children: [
                ScoreRing(
                  score: (session.overallScore ?? session.averageScore).round(),
                  max: 10,
                  caption: 'of 10',
                ),
                const SizedBox(width: TackSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${session.role} practice', style: TackText.cardTitle),
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
                    Text(session.strongestArea!, style: TackText.rowTitle),
                    const SizedBox(height: TackSpace.md),
                  ],
                  if (session.weakestArea != null) ...[
                    Text('WORTH PRACTISING', style: TackText.monoLabel),
                    const SizedBox(height: 4),
                    Text(session.weakestArea!, style: TackText.rowTitle),
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
                      const TackPill(
                        'Skipped',
                        background: TackColors.line,
                        foreground: TackColors.muted,
                      )
                    else if (question.feedback != null)
                      TackPill.teal(question.feedback!.score.toStringAsFixed(1)),
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
