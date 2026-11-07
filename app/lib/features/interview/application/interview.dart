/// The interview feature's application layer: everything its screens use
/// besides the design system and the router.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../core/supabase/client.dart';
import '../data/interview_catalog.dart';
import '../data/interview_models.dart';
import '../data/interview_repository.dart';

export '../../profile/application/profile.dart' show modeProvider;
export '../../score/application/score.dart' show readinessProvider;
export '../data/interview_catalog.dart';
export '../data/interview_models.dart';
export '../data/interview_repository.dart'
    show
        interviewRepositoryProvider,
        interviewHistoryProvider,
        companyPacksProvider,
        dueQuestionsProvider;
export 'practice_copy.dart';

/// Every role by field, and the role suggested to this student. Empty when
/// signed out.
final interviewCatalogProvider = FutureProvider.autoDispose<InterviewCatalog>((
  ref,
) async {
  if (ref.watch(currentUserProvider)?.id == null) return InterviewCatalog.empty;
  return ref.watch(interviewRepositoryProvider).catalog();
});

final interviewAnalyticsProvider = Provider<InterviewAnalytics>(
  (ref) => InterviewAnalytics(ref.watch(analyticsProvider)),
);

/// The interview events of contract C5.4. Fixed ids only: never a title, a
/// question or an answer.
class InterviewAnalytics {
  const InterviewAnalytics(this._analytics);

  final Analytics _analytics;

  void started({
    String? roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool pack,
  }) {
    _analytics.track(
      'interview_started',
      properties: {
        if (!pack && roleSlug != null) 'role': roleSlug,
        'session_type': type.name,
        'difficulty': difficulty.name,
        'kind': pack ? 'pack' : 'pool',
      },
    );
  }
}
