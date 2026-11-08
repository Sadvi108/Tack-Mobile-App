import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';

import '../application/interview.dart';
import 'question_view.dart';
import 'review_view.dart';
import 'setup_view.dart';
import 'summary_view.dart';

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
  List<DueQuestion>? _reviewing;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final reviewing = _reviewing;

    if (reviewing != null) {
      return ReviewView(
        questions: reviewing,
        onDone: () {
          ref.invalidate(dueQuestionsProvider);
          setState(() => _reviewing = null);
        },
      );
    }
    if (session == null) {
      return InterviewSetupView(
        busy: _busy,
        onStart: _start,
        onStartPack: _startPack,
        onPractiseAgain: (due) => setState(() => _reviewing = due),
      );
    }
    if (session.isComplete) {
      return SummaryView(
        session: session,
        onAgain: () => setState(() => _session = null),
      );
    }
    return QuestionView(
      session: session,
      onAnswered: (updated) => setState(() => _session = updated),
      onFinished: _complete,
    );
  }

  /// Starting from a company pack.
  ///
  /// Separate from [_start] because it touches no Edge Function and no model:
  /// the questions are seeded reference data, so this is an insert and
  /// nothing else.
  Future<void> _startPack(CompanyPack pack, bool timer) async {
    setState(() => _busy = true);
    try {
      final session = await ref
          .read(interviewRepositoryProvider)
          .startFromPack(pack: pack, timerEnabled: timer);
      ref
          .read(interviewAnalyticsProvider)
          .started(
            type: InterviewType.mixed,
            difficulty: Difficulty.medium,
            pack: true,
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

  /// Starting from the role's question pool. Free: the database draws the
  /// questions and writes the session; no model and no AI action.
  Future<void> _start({
    required InterviewRole role,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timer,
  }) async {
    setState(() => _busy = true);
    try {
      final session = await ref
          .read(interviewRepositoryProvider)
          .startPractice(
            roleSlug: role.slug,
            type: type,
            difficulty: difficulty,
            timerEnabled: timer,
          );
      ref
          .read(interviewAnalyticsProvider)
          .started(
            roleSlug: role.slug,
            type: type,
            difficulty: difficulty,
            pack: false,
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
      final done = await ref
          .read(interviewRepositoryProvider)
          .complete(session);
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
