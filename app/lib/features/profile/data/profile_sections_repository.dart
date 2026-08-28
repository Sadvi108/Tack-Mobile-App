import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'education_stage.dart';
import 'profile_sections.dart';

/// Everything on the profile beyond the core fields.
///
/// Reads and writes are scoped by the caller's own id here, not only by Row
/// Level Security, so a mistake in one query cannot widen into a leak.
class ProfileSectionsRepository {
  const ProfileSectionsRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<Map<ProfileSection, List<ProfileEntry>>> loadAll() async {
    try {
      final results = await Future.wait([
        _db
            .from('education')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db
            .from('courses')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null)
            .order('semester_order'),
        _db
            .from('projects')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db
            .from('experiences')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db
            .from('activities')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db
            .from('certifications')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db
            .from('portfolio_links')
            .select()
            .eq('user_id', _uid)
            .isFilter('deleted_at', null),
        _db.from('student_interests').select().eq('user_id', _uid),
      ]);

      final interests = results[7];

      return {
        ProfileSection.education: results[0]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: (r['degree'] as String?) ?? 'Degree',
                subtitle: r['university_name'] as String?,
                meta: r['graduation_year'] == null
                    ? null
                    : 'Graduating ${r['graduation_year']}',
              ),
            )
            .toList(),
        ProfileSection.courses: results[1]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['title'] as String,
                subtitle: r['code'] as String?,
                meta: r['grade'] as String?,
              ),
            )
            .toList(),
        ProfileSection.projects: results[2]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['title'] as String,
                detail: r['summary'] as String?,
                meta: r['url'] as String?,
              ),
            )
            .toList(),
        ProfileSection.experience: results[3]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['title'] as String,
                subtitle: r['company_name'] as String?,
                detail: r['description'] as String?,
              ),
            )
            .toList(),
        ProfileSection.activities: results[4]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['title'] as String,
                subtitle: r['organisation'] as String?,
                meta: r['category'] as String?,
              ),
            )
            .toList(),
        ProfileSection.certifications: results[5]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['title'] as String,
                subtitle: r['issuer'] as String?,
              ),
            )
            .toList(),
        ProfileSection.portfolio: results[6]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['kind'] as String,
                subtitle: r['url'] as String?,
              ),
            )
            .toList(),
        // Favourite subjects and favourite courses are the same question
        // asked of different students, so they share a section.
        ProfileSection.favourites: interests
            .where(
              (r) =>
                  r['kind'] == 'favourite_subject' ||
                  r['kind'] == 'favourite_course',
            )
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['label'] as String,
              ),
            )
            .toList(),
        ProfileSection.hobbies: interests
            .where((r) => r['kind'] == 'hobby' || r['kind'] == 'interest')
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: r['label'] as String,
              ),
            )
            .toList(),
      };
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<UserSkill>> skills() async {
    try {
      final rows = await _db
          .from('user_skills')
          .select('id, skill_id, proficiency, source, skills(name)')
          .eq('user_id', _uid);
      final list = rows.map(UserSkill.fromRow).toList()
        ..sort((a, b) => b.proficiency.compareTo(a.proficiency));
      return list;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> setProficiency(String userSkillId, int proficiency) async {
    try {
      await _db
          .from('user_skills')
          .update({'proficiency': proficiency.clamp(1, 5)})
          .eq('id', userSkillId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> addSkill(String skillId) async {
    try {
      await _db
          .from('user_skills')
          .upsert(
            {
              'user_id': _uid,
              'skill_id': skillId,
              'proficiency': 2,
              'source': 'self',
            },
            onConflict: 'user_id,skill_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Adds one subject, course or hobby. The section decides the kind, and the
  /// stage decides whether a favourite is a subject or a course.
  Future<void> addInterest({
    required ProfileSection section,
    required String label,
    required bool atSchool,
  }) async {
    final kind = switch (section) {
      ProfileSection.hobbies => InterestKind.hobby,
      _ =>
        atSchool ? InterestKind.favouriteSubject : InterestKind.favouriteCourse,
    };
    try {
      await _db
          .from('student_interests')
          .upsert(
            {'user_id': _uid, 'kind': kind.wire, 'label': label.trim()},
            onConflict: 'user_id,kind,label',
            ignoreDuplicates: true,
          );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> insert(
    ProfileSection section,
    Map<String, Object?> values,
  ) async {
    try {
      await _db.from(section.table).insert({...values, 'user_id': _uid});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Soft delete everywhere it is supported. Portfolio links and skills are
  /// the only rows small enough to remove outright.
  Future<void> remove(ProfileSection section, String id) async {
    try {
      if (section == ProfileSection.skills ||
          section == ProfileSection.portfolio ||
          section == ProfileSection.favourites ||
          section == ProfileSection.hobbies) {
        await _db.from(section.table).delete().eq('id', id).eq('user_id', _uid);
      } else {
        await _db
            .from(section.table)
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id)
            .eq('user_id', _uid);
      }
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final profileSectionsRepositoryProvider = Provider<ProfileSectionsRepository>(
  (ref) => ProfileSectionsRepository(ref.watch(supabaseProvider)),
);

final profileSectionsProvider =
    FutureProvider<Map<ProfileSection, List<ProfileEntry>>>((ref) async {
      if (!ref.watch(isSignedInProvider)) return const {};
      return ref.watch(profileSectionsRepositoryProvider).loadAll();
    });

final userSkillsProvider = FutureProvider<List<UserSkill>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(profileSectionsRepositoryProvider).skills();
});
