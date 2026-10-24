import '../../../core/supabase/client.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../data/analysis_models.dart';
import '../../coach/data/coach_repository.dart';
import '../data/analysis_repository.dart';

/// Runs an analysis and follows it to completion.
///
/// The endpoint returns immediately with a job id. The controller then listens
/// for the job's row to change, so the result appears the moment the worker
/// saves it, and the student can leave the screen and come back. Nothing
/// blocks.
///
/// It used to ask every three seconds. Now it asks when the row changes, plus
/// a slow safety check in case the live connection missed it. If the
/// connection drops, it goes back to asking every few seconds.
class AnalyserController extends Notifier<AnalysisState> {
  /// While the live connection is up: a change it missed.
  static const _safetyCheck = Duration(seconds: 30);

  /// Once the live connection has dropped.
  static const _fallbackCheck = Duration(seconds: 3);

  /// Allows the cron interval and bounded worker retries.
  static const _giveUpAfter = Duration(minutes: 12);

  String? _following;
  StreamSubscription<void>? _changes;
  Timer? _check;
  Timer? _giveUp;

  @override
  AnalysisState build() {
    final userId = ref.watch(currentUserProvider)?.id;
    ref.onDispose(_stopFollowing);
    if (userId != null) Future.microtask(() => _restore(userId));
    return const AnalysisIdle();
  }

  Future<void> _restore(String userId) async {
    try {
      final repo = ref.read(analysisRepositoryProvider);
      final id = await repo.latestJob();
      if (!ref.mounted ||
          ref.read(currentUserProvider)?.id != userId ||
          state is! AnalysisIdle ||
          id == null) {
        return;
      }
      final result = await repo.poll(id);
      if (!ref.mounted || state is! AnalysisIdle) return;
      state = result ?? AnalysisQueued(id);
      if (result == null) _follow(id);
    } catch (_) {
      /* The saved job remains discoverable after reconnect. */
    }
  }

  void reset() {
    _stopFollowing();
    state = const AnalysisIdle();
  }

  Future<void> analyse(String text, {String? jobId}) async {
    _stopFollowing();
    state = const AnalysisQueued(null);

    try {
      final result = await ref
          .read(analysisRepositoryProvider)
          .submit(text, jobId: jobId);
      state = result;
      // Quota is spent on submission, so refresh the count either way.
      ref.invalidate(aiAllowanceProvider);

      if (result is AnalysisQueued && result.jobId != null) {
        _follow(result.jobId!);
      }
    } catch (e) {
      state = AnalysisFailed(Failure.from(e).message);
    }
  }

  void _follow(String jobId) {
    _stopFollowing();
    _following = jobId;
    _check = Timer.periodic(_safetyCheck, (_) => _read(jobId));
    _giveUp = Timer(_giveUpAfter, () {
      _stopFollowing();
      state = const AnalysisFailed(
        'This is taking longer than usual. Check back in a few minutes.',
      );
    });

    void checkOften() {
      _check?.cancel();
      _check = Timer.periodic(_fallbackCheck, (_) => _read(jobId));
    }

    try {
      _changes = ref
          .read(analysisRepositoryProvider)
          .jobChanges(jobId)
          .listen(
            (_) => _read(jobId),
            // A dropped connection is not a failed analysis.
            onError: (Object _) => checkOften(),
          );
    } catch (_) {
      checkOften();
    }
  }

  Future<void> _read(String jobId) async {
    try {
      final result = await ref.read(analysisRepositoryProvider).poll(jobId);
      if (result == null || !ref.mounted || _following != jobId) return;
      _stopFollowing();
      state = result;
      ref.invalidate(aiAllowanceProvider);
    } catch (_) {
      // A dropped read is not a failed analysis; the next check tries again.
    }
  }

  void _stopFollowing() {
    _following = null;
    _check?.cancel();
    _check = null;
    _giveUp?.cancel();
    _giveUp = null;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.cancel());
  }
}

final analyserControllerProvider =
    NotifierProvider<AnalyserController, AnalysisState>(AnalyserController.new);
