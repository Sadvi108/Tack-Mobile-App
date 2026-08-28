import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../domain/flow_config.dart';

/// One in-progress onboarding.
class OnboardingDraft {
  const OnboardingDraft({
    required this.currentStep,
    required this.answers,
    this.branch,
    this.completedAt,
  });

  final String currentStep;
  final OnboardingBranch? branch;
  final Map<String, dynamic> answers;
  final DateTime? completedAt;

  static const empty = OnboardingDraft(currentStep: 'basics', answers: {});

  bool get isComplete => completedAt != null;

  T? value<T>(String key) => answers[key] as T?;

  List<String> stringList(String key) {
    final raw = answers[key];
    if (raw is List) return raw.map((e) => '$e').toList();
    return const [];
  }

  factory OnboardingDraft.fromRow(Map<String, dynamic> row) => OnboardingDraft(
    currentStep: (row['current_step'] as String?) ?? 'basics',
    branch: switch (row['branch'] as String?) {
      'primary' => OnboardingBranch.primary,
      'high_school' => OnboardingBranch.highSchool,
      'bachelors' => OnboardingBranch.bachelors,
      'graduated' => OnboardingBranch.graduated,
      _ => null,
    },
    answers: (row['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
    completedAt: DateTime.tryParse('${row['completed_at']}'),
  );
}

/// Reads and writes the draft.
///
/// Answers are saved after every step, so closing the app mid-flow costs
/// nothing. The real tables are written once, at the end, by a database
/// function that runs in a single transaction.
class DraftRepository {
  const DraftRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<OnboardingDraft> load() async {
    try {
      final row = await _db
          .from('onboarding_drafts')
          .select()
          .eq('user_id', _uid)
          .maybeSingle();
      return row == null ? OnboardingDraft.empty : OnboardingDraft.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Merges this step's answers into the draft and moves the cursor.
  ///
  /// Last write wins if the same account is open in two places: the answers
  /// are merged rather than replaced, so the two do not clobber each other's
  /// unrelated fields.
  Future<OnboardingDraft> saveStep({
    required String stepId,
    required Map<String, dynamic> answers,
    required String nextStepId,
    OnboardingBranch? branch,
  }) async {
    try {
      final existing = await load();
      final merged = {...existing.answers, ...answers};

      final row = await _db
          .from('onboarding_drafts')
          .upsert({
            'user_id': _uid,
            'current_step': nextStepId,
            'branch': branch?.wire ?? existing.branch?.wire,
            'answers': merged,
          }, onConflict: 'user_id')
          .select()
          .single();

      return OnboardingDraft.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Writes everything into the real tables and returns the first score.
  ///
  /// The database does this in one transaction and it is safe to call twice.
  Future<int> submit(Map<String, dynamic> answers) async {
    try {
      final result = await _db.rpc<dynamic>(
        'submit_onboarding',
        params: {'p_answers': answers},
      );
      final row = result is List ? result.firstOrNull : result;
      if (row is Map && row['total'] != null) {
        return (row['total'] as num).toInt();
      }
      return 0;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Records an email and stops. No account, no profile.
  Future<void> joinWaitlist({required String email, String? countryId}) async {
    try {
      await _db
          .from('waitlist')
          .upsert(
            {
              'email': email.trim().toLowerCase(),
              'stage_requested': 'primary',
              'country_id': countryId,
            },
            onConflict: 'email',
            ignoreDuplicates: true,
          );
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final draftRepositoryProvider = Provider<DraftRepository>(
  (ref) => DraftRepository(ref.watch(supabaseProvider)),
);

final onboardingDraftProvider = FutureProvider<OnboardingDraft>((ref) async {
  if (!ref.watch(isSignedInProvider)) return OnboardingDraft.empty;
  return ref.watch(draftRepositoryProvider).load();
});
