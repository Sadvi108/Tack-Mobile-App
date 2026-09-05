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
    ref.onDispose(() => _poll?.cancel());
    return const AnalysisIdle();
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
      // Roughly two minutes. Longer than that and something is wrong with the
      // worker, not with the student's connection.
      if (attempts > 40) {
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
          state = result;
        }
      } catch (_) {
        // A dropped poll is not a failed analysis; the next tick tries again.
      }
    });
  }
}

final analyserControllerProvider =
    NotifierProvider<AnalyserController, AnalysisState>(AnalyserController.new);
