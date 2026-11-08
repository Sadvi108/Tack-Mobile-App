import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

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

  /// The company a pack session came from, so its questions say who wrote
  /// them. Null for pool sessions.
  String? _packName;

  /// Opened at /interview/review: straight into Practise again. Read once.
  /// matchedLocation, not uri: in go_router 16 every page in the stack sees
  /// the full location, so the setup page under a review page would read
  /// /interview/review too (plan Appendix B, item 4).
  bool? _reviewRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reviewRoute ??=
        GoRouter.maybeOf(context) != null &&
        GoRouterState.of(context).matchedLocation == Routes.interviewReview;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final reviewing = _reviewing;

    if (_reviewRoute == true && reviewing == null && session == null) {
      return _reviewEntry();
    }
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
        onAgain: () => setState(() {
          _session = null;
          _packName = null;
        }),
      );
    }
    return QuestionView(
      session: session,
      packName: _packName,
      onAnswered: (updated) => setState(() => _session = updated),
      onFinished: _complete,
    );
  }

  /// Practise again as a destination of its own: what is due, or what to do
  /// when nothing is.
  Widget _reviewEntry() {
    void back() => tackBack(context, fallback: Routes.interview);
    final header = TackHeader(title: 'Practise again', onBack: back);

    return ref
        .watch(dueQuestionsProvider)
        .when(
          data: (due) => due.isEmpty
              ? TackScaffold(
                  header: header,
                  body: TackEmptyState(
                    title: 'Practise an interview first',
                    body:
                        'Answers you practise come back here after a few '
                        'days, so you can try them again for free.',
                    primaryLabel: 'Start practising',
                    onPrimary: () => context.pushReplacement(Routes.interview),
                  ),
                )
              : ReviewView(
                  questions: due,
                  onDone: () {
                    ref.invalidate(dueQuestionsProvider);
                    back();
                  },
                ),
          loading: () => TackScaffold(
            header: header,
            body: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TackSkeleton(height: 24),
                SizedBox(height: TackSpace.md),
                TackSkeleton(height: 96),
              ],
            ),
          ),
          error: (error, _) => TackScaffold(
            header: header,
            body: TackErrorState(
              body: Failure.from(error).message,
              onRetry: () => ref.invalidate(dueQuestionsProvider),
            ),
          ),
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
        _packName = pack.name;
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
