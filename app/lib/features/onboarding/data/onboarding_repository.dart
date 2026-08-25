import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../profile/data/education_stage.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import 'onboarding_steps.dart';

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
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<Profile> saveStep(int step, Map<String, Object?> patch) =>
      _profiles.update({...patch, 'onboarding_step': step});

  /// Writes the one current education record, whichever kind it is.
  ///
  /// A school and a university live in the same table: the columns that do not
  /// apply are simply left null, which is cheaper to reason about than two
  /// tables that are ninety per cent the same.
  Future<Profile> saveEducation({
    required int step,
    required EducationStage stage,
    String? universityId,
    String? institutionName,
    String? degree,
    String? fieldOfStudy,
    String? classLevel,
    String? currentGrade,
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
        'stage': stage.wire,
        'university_id': universityId,
        'institution_name': institutionName,
        'university_name': institutionName,
        'degree': degree,
        'field_of_study': fieldOfStudy,
        'class_level': classLevel,
        'current_grade': currentGrade,
        'graduation_year': graduationYear,
        'cgpa': cgpa,
        'cgpa_scale': cgpaScale,
        // A graduate is no longer studying, so this record is history.
        'is_current': stage != EducationStage.graduated,
      };

      if (existing == null) {
        await _db.from('education').insert(row);
      } else {
        await _db
            .from('education')
            .update(row)
            .eq('id', existing['id'] as String);
      }
    } catch (e) {
      throw Failure.from(e);
    }
    return _profiles.update({'onboarding_step': step});
  }

  /// Replaces every interest of the given kinds with exactly this set.
  ///
  /// Scoped by kind so saving favourite subjects does not wipe hobbies.
  Future<void> saveInterests({
    required Set<InterestKind> kinds,
    required List<({InterestKind kind, String label})> entries,
  }) async {
    try {
      await _db.from('student_interests').delete().eq('user_id', _uid).inFilter(
        'kind',
        [for (final k in kinds) k.wire],
      );

      if (entries.isNotEmpty) {
        await _db
            .from('student_interests')
            .upsert(
              [
                for (final entry in entries)
                  {
                    'user_id': _uid,
                    'kind': entry.kind.wire,
                    'label': entry.label.trim(),
                  },
              ],
              onConflict: 'user_id,kind,label',
              ignoreDuplicates: true,
            );
      }
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<StudentInterest>> savedInterests() async {
    try {
      final rows = await _db
          .from('student_interests')
          .select('id, kind, label')
          .eq('user_id', _uid);
      return rows.map(StudentInterest.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<Country>> countries() async {
    try {
      final rows = await _db
          .from('countries')
          .select('id, iso2, name, dial_code')
          .order('sort_order');
      return rows.map(Country.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Replaces the student's self-declared skills with exactly this set.
  /// Skills that came from a CV or a course are left alone — only the ones the
  /// student picked here are theirs to replace.
  Future<Profile> saveSkills({
    required int step,
    required Set<String> skillIds,
  }) async {
    try {
      await _db
          .from('user_skills')
          .delete()
          .eq('user_id', _uid)
          .eq('source', 'self');
      if (skillIds.isNotEmpty) {
        await _db
            .from('user_skills')
            .upsert(
              [
                for (final id in skillIds)
                  {
                    'user_id': _uid,
                    'skill_id': id,
                    'proficiency': 2,
                    'source': 'self',
                  },
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
    String? targetRole,
    List<String> targetIndustry = const [],
    String? intendedField,
    String? passion,
  }) => _profiles.update({
    'target_role': targetRole,
    'target_industry': targetIndustry,
    'intended_field': intendedField,
    'passion': passion,
    'onboarding_step': OnboardingStep.values.length,
    'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Which self-declared skills are already saved, so a resumed session shows
  /// the student's earlier picks rather than an empty grid.
  Future<Set<String>> savedSkillIds() async {
    try {
      final rows = await _db
          .from('user_skills')
          .select('skill_id')
          .eq('user_id', _uid);
      return rows.map((r) => r['skill_id'] as String).toSet();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Map<String, Object?>?> savedEducation() async {
    try {
      return await _db
          .from('education')
          .select(
            'university_id, university_name, degree, field_of_study, graduation_year, cgpa, cgpa_scale',
          )
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .eq('is_current', true)
          .maybeSingle();
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(
    ref.watch(supabaseProvider),
    ref.watch(profileRepositoryProvider),
  ),
);
