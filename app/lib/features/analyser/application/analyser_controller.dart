import '../../../core/supabase/client.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../data/analysis_models.dart';
import '../../coach/data/coach_repository.dart';
import '../data/analysis_repository.dart';

/// Runs an analysis and follows it to completion.
///
/// The endpoint returns immediately with a job id; this polls for the result
/// so the student can leave the screen and come back. Nothing blocks.
class AnalyserController extends Notifier<AnalysisState> {
  Timer? _poll;

  @override
  AnalysisState build() {
    final userId = ref.watch(currentUserProvider)?.id;
    ref.onDispose(() => _poll?.cancel());
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
      if (result == null) _startPolling(id);
    } catch (_) {
      /* The saved job remains discoverable after reconnect. */
    }
  }

  void reset() {
    _poll?.cancel();
    state = const AnalysisIdle();
  }

  Future<void> analyse(String text) async {
    _poll?.cancel();
    state = const AnalysisQueued(null);

    try {
      final result = await ref.read(analysisRepositoryProvider).submit(text);
      state = result;
      // Quota is spent on submission, so refresh the count either way.
      ref.invalidate(aiAllowanceProvider);

      if (result is AnalysisQueued && result.jobId != null) {
        _startPolling(result.jobId!);
      }
    } catch (e) {
      state = AnalysisFailed(Failure.from(e).message);
    }
  }

  void _startPolling(String jobId) {
    var attempts = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      // Allow the cron interval and bounded worker retries.
      if (attempts > 240) {
        timer.cancel();
        state = const AnalysisFailed(
          'This is taking longer than usual. Check back in a few minutes.',
        );
        return;
      }

      try {
        final result = await ref.read(analysisRepositoryProvider).poll(jobId);
        if (result != null) {
          timer.cancel();
          if (!ref.mounted) return;
          state = result;
          ref.invalidate(aiAllowanceProvider);
        }
      } catch (_) {
        // A dropped poll is not a failed analysis; the next tick tries again.
      }
    });
  }
}

final analyserControllerProvider =
    NotifierProvider<AnalyserController, AnalysisState>(AnalyserController.new);
