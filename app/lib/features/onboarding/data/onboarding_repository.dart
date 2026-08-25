import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';

/// Writes onboarding answers.
///
/// Every step saves as soon as it is answered. A student on a bus with a
/// dropping connection must never lose work they already did, so nothing is
/// batched to the end.
class OnboardingRepository {
  const OnboardingRepository(this._db, this._profiles);

  final SupabaseClient _db;
  final ProfileRepository _profiles;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const Failure('You are signed out. Log in and try again.');
    return id;
  }

  Future<Profile> saveStep(int step, Map<String, Object?> patch) =>
      _profiles.update({...patch, 'onboarding_step': step});

  Future<Profile> saveEducation({
    required int step,
    String? universityId,
    String? universityName,
    String? degree,
    String? fieldOfStudy,
    int? graduationYear,
    double? cgpa,
    double cgpaScale = 4.0,
  }) async {
    try {
      final existing = await _db
          .from('education')
          .select('id')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .eq('is_current', true)
          .maybeSingle();

      final row = {
        'user_id': _uid,
        'university_id': universityId,
        'university_name': universityName,
        'degree': degree,
        'field_of_study': fieldOfStudy,
        'graduation_year': graduationYear,
        'cgpa': cgpa,
        'cgpa_scale': cgpaScale,
        'is_current': true,
      };

      if (existing == null) {
        await _db.from('education').insert(row);
      } else {
        await _db.from('education').update(row).eq('id', existing['id'] as String);
      }
    } catch (e) {
      throw Failure.from(e);
    }
    return _profiles.update({'onboarding_step': step});
  }

  /// Replaces the student's self-declared skills with exactly this set.
  /// Skills that came from a CV or a course are left alone — only the ones the
  /// student picked here are theirs to replace.
  Future<Profile> saveSkills({required int step, required Set<String> skillIds}) async {
    try {
      await _db.from('user_skills').delete().eq('user_id', _uid).eq('source', 'self');
      if (skillIds.isNotEmpty) {
        await _db.from('user_skills').upsert(
              [
                for (final id in skillIds)
                  {'user_id': _uid, 'skill_id': id, 'proficiency': 2, 'source': 'self'},
              ],
              onConflict: 'user_id,skill_id',
              ignoreDuplicates: true,
            );
      }
    } catch (e) {
      throw Failure.from(e);
    }
    return _profiles.update({'onboarding_step': step});
  }

  Future<Profile> complete({
    required String targetRole,
    required List<String> targetIndustry,
  }) =>
      _profiles.update({
        'target_role': targetRole,
        'target_industry': targetIndustry,
        'onboarding_step': OnboardingStep.values.length,
        'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// Which self-declared skills are already saved, so a resumed session shows
  /// the student's earlier picks rather than an empty grid.
  Future<Set<String>> savedSkillIds() async {
    try {
      final rows = await _db.from('user_skills').select('skill_id').eq('user_id', _uid);
      return rows.map((r) => r['skill_id'] as String).toSet();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Map<String, Object?>?> savedEducation() async {
    try {
      return await _db
          .from('education')
          .select('university_id, university_name, degree, field_of_study, graduation_year, cgpa, cgpa_scale')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .eq('is_current', true)
          .maybeSingle();
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

/// The five steps, in order. Each one asks for a single kind of thing so it
/// clears in under 30 seconds.
enum OnboardingStep {
  you,
  education,
  year,
  skills,
  target;

  String get title => switch (this) {
        OnboardingStep.you => 'About you',
        OnboardingStep.education => 'Where you study',
        OnboardingStep.year => 'Where you are',
        OnboardingStep.skills => 'What you can do',
        OnboardingStep.target => 'What you want',
      };

  String get blurb => switch (this) {
        OnboardingStep.you => 'So the app can address you properly.',
        OnboardingStep.education => 'Your CGPA is optional and is never shown to anyone.',
        OnboardingStep.year =>
          'This one answer shapes the whole app. You can change it any time from your profile.',
        OnboardingStep.skills => 'Pick anything you have done, even at a beginner level.',
        OnboardingStep.target => 'A rough idea is enough. Nothing here is locked in.',
      };
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(
    ref.watch(supabaseProvider),
    ref.watch(profileRepositoryProvider),
  ),
);
