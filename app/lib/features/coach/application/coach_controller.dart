import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/allowance.dart';
import '../../../core/analytics.dart';
import '../../../core/failure.dart';
import '../../profile/application/profile.dart';
import '../data/coach_models.dart';
import '../data/coach_repository.dart';

/// Where a question is between being typed and being answered.
sealed class CoachPhase {
  const CoachPhase();
}

class CoachIdle extends CoachPhase {
  const CoachIdle();
}

/// Waiting on the coach endpoint: a free answer usually comes straight back.
class CoachSending extends CoachPhase {
  const CoachSending();
}

/// The question went to the model (202). The answer is saved in the
/// conversation whether or not the student stays.
class CoachWaiting extends CoachPhase {
  const CoachWaiting(this.jobId);
  final String jobId;
}

/// It did not go through. [retry] sends the same question with the same
/// [operationId], so it can never be charged or answered twice.
class CoachFailed extends CoachPhase {
  const CoachFailed({
    required this.question,
    required this.operationId,
    required this.message,
  });

  final String question;
  final String operationId;
  final String message;
}

/// Today's AI actions are used. The free questions still work.
class CoachQuota extends CoachPhase {
  const CoachQuota(this.message);
  final String message;
}

class CoachState {
  const CoachState({
    this.threadId,
    this.messages = const [],
    this.phase = const CoachIdle(),
    this.loading = false,
    this.restored = false,
  });

  final String? threadId;
  final List<ChatMessage> messages;
  final CoachPhase phase;

  /// The saved conversation has not been read yet.
  final bool loading;

  /// The saved conversation has been adopted, which happens once.
  final bool restored;

  bool get busy => phase is CoachSending || phase is CoachWaiting;

  CoachState copyWith({
    String? threadId,
    List<ChatMessage>? messages,
    CoachPhase? phase,
    bool? loading,
    bool? restored,
  }) => CoachState(
    threadId: threadId ?? this.threadId,
    messages: messages ?? this.messages,
    phase: phase ?? this.phase,
    loading: loading ?? this.loading,
    restored: restored ?? this.restored,
  );
}

/// Said when a question could not leave the phone. Never "saved" or "sync":
/// nothing was kept.
const coachOfflineMessage =
    'You are offline. Your question was not sent. Connect and send it again.';

/// The day's AI actions are used. A trade that keeps Tack free, never a
/// telling-off, and never the daily number.
const coachQuotaMessage =
    "Today's AI actions are used. The daily limit is what keeps Tack free. "
    'More arrive at midnight, Bangladesh time. These questions are always '
    'free:';

/// The conversation on the coach screen, and every way a question can go.
class CoachController extends Notifier<CoachState> {
  @override
  CoachState build() {
    ref.listen(coachHistoryProvider, (_, next) {
      if (next.hasValue) {
        restore(next.requireValue);
      } else if (next.hasError && state.loading) {
        // Nothing to adopt: the opening screen is still useful.
        state = state.copyWith(loading: false);
      }
    });
    final now = ref.read(coachHistoryProvider);
    if (now.hasValue) {
      final (threadId, messages) = now.requireValue;
      return CoachState(threadId: threadId, messages: messages, restored: true);
    }
    return CoachState(loading: !now.hasError);
  }

  /// Adopts the saved conversation once. A line the student sent while it
  /// was loading stays after it.
  void restore((String?, List<ChatMessage>) history) {
    if (state.restored) return;
    final (threadId, saved) = history;
    state = state.copyWith(
      threadId: state.threadId ?? threadId,
      messages: [...saved, ...state.messages],
      loading: false,
      restored: true,
    );
  }

  Future<void> send(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    final operationId = newOperationId();
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          id: 'local-$operationId',
          role: 'student',
          body: text,
          createdAt: DateTime.now(),
        ),
      ],
      phase: const CoachSending(),
    );
    await _ask(text, operationId);
  }

  /// Sends the failed question again, as the same operation: no new bubble,
  /// no second charge.
  Future<void> retry() async {
    final failed = state.phase;
    if (failed is! CoachFailed) return;
    state = state.copyWith(phase: const CoachSending());
    await _ask(failed.question, failed.operationId);
  }

  /// Records which chip was tapped: a fixed route id and the year, nothing
  /// the student wrote.
  void recordTap(CoachAction action, YearMode mode) {
    ref
        .read(analyticsProvider)
        .track(
          'coach_action_tapped',
          properties: {'route': action.route, 'mode': mode.name},
        );
  }

  Future<void> _ask(String question, String operationId) async {
    try {
      final reply = await ref
          .read(coachRepositoryProvider)
          .ask(
            question,
            threadId: state.threadId,
            operationId: operationId,
            onQueued: (jobId) {
              if (ref.mounted) {
                state = state.copyWith(phase: CoachWaiting(jobId));
              }
            },
          );
      if (!ref.mounted) return;
      final body = reply.body;
      state = state.copyWith(
        threadId: reply.threadId,
        messages: [
          ...state.messages,
          if (body != null)
            ChatMessage(
              id: 'local-reply-$operationId',
              role: 'coach',
              body: body,
              createdAt: DateTime.now(),
              answeredBy: reply.answeredBy,
              citations: reply.citations,
              fromGuides: reply.fromGuides,
              actions: reply.actions,
              intent: reply.intent,
            ),
        ],
        phase: const CoachIdle(),
      );
      ref.invalidate(aiAllowanceProvider);
      // The saved conversation now has this reply in it.
      ref.invalidate(coachHistoryProvider);
    } catch (e) {
      if (!ref.mounted) return;
      final failure = Failure.from(e);
      if (failure.code == 'quota_exhausted') {
        state = state.copyWith(phase: const CoachQuota(coachQuotaMessage));
        ref.invalidate(aiAllowanceProvider);
        return;
      }
      state = state.copyWith(
        phase: CoachFailed(
          question: question,
          operationId: operationId,
          message: failure.isOffline ? coachOfflineMessage : failure.message,
        ),
      );
    }
  }
}

final coachControllerProvider =
    NotifierProvider.autoDispose<CoachController, CoachState>(
      CoachController.new,
    );
