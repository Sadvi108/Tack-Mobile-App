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
        // education_profiles, not education. Onboarding writes the first and
        // readiness_ratios reads it; this screen was reading the second, and so
        // told a student who had just answered every question to "add where you
        // study". One fact, one table.
        _db
            .from('education_profiles')
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
        // Onboarding writes what a student picked from the curated lists into
        // these two; the sheet on this screen writes free text into
        // student_interests. Both are the student's answer, so both are read.
        _db
            .from('user_subjects')
            .select('id, sentiment, subjects(name)')
            .eq('user_id', _uid),
        _db
            .from('user_interests')
            .select('id, label, interests(name)')
            .eq('user_id', _uid),
      ]);

      final interests = results[7];
      final subjects = results[8];
      final picked = results[9];

      return {
        ProfileSection.education: results[0]
            .map(
              (r) => ProfileEntry(
                id: r['id'] as String,
                title: (r['institution_name'] as String?) ?? 'Where you study',
                subtitle: _stageLabel(r['stage'] as String?),
                detail: _gpaLabel(r['gpa'], r['gpa_scale']),
                meta: r['expected_end_year'] == null
                    ? null
                    : 'Finishing ${r['expected_end_year']}',
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
        ProfileSection.favourites: [
          for (final r in subjects.where((r) => r['sentiment'] == 'loves'))
            ProfileEntry(
              id: 'user_subjects:${r['id']}',
              title:
                  ((r['subjects'] as Map?)?['name'] as String?) ?? 'A subject',
            ),
          for (final r in interests.where(
            (r) =>
                r['kind'] == 'favourite_subject' ||
                r['kind'] == 'favourite_course',
          ))
            ProfileEntry(
              id: 'student_interests:${r['id']}',
              title: r['label'] as String,
            ),
        ],
        ProfileSection.hobbies: [
          for (final r in picked)
            ProfileEntry(
              id: 'user_interests:${r['id']}',
              title:
                  ((r['interests'] as Map?)?['name'] as String?) ??
                  (r['label'] as String?) ??
                  'An interest',
            ),
          for (final r in interests.where(
            (r) => r['kind'] == 'hobby' || r['kind'] == 'interest',
          ))
            ProfileEntry(
              id: 'student_interests:${r['id']}',
              title: r['label'] as String,
            ),
        ],
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
      // education_profiles holds one row per student — the column is unique —
      // so saving it again edits that record rather than adding a second
      // account of where the same person studies.
      if (section == ProfileSection.education) {
        await _db.from(section.table).upsert({
          ...values,
          'user_id': _uid,
        }, onConflict: 'user_id');
        return;
      }
      await _db.from(section.table).insert({...values, 'user_id': _uid});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Soft delete everywhere it is supported. Portfolio links and skills are
  /// the only rows small enough to remove outright.
  Future<void> remove(ProfileSection section, String id) async {
    try {
      // Favourites and hobbies are read from more than one table, so an entry
      // carries the table it came from. Splitting it here keeps that detail
      // out of the widget that draws the row.
      if (id.contains(':')) {
        final table = id.substring(0, id.indexOf(':'));
        final rowId = id.substring(id.indexOf(':') + 1);
        await _db.from(table).delete().eq('id', rowId).eq('user_id', _uid);
        return;
      }

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

/// Just the write the add-or-edit sheet performs.
///
/// A function rather than the whole repository, so a widget test can stand in
/// for it with a closure. Faking the repository itself means constructing a
/// SupabaseClient, and a live client schedules timers that outlive the test.
typedef SectionInsert =
    Future<void> Function(ProfileSection section, Map<String, Object?> values);

final sectionInsertProvider = Provider<SectionInsert>(
  (ref) => ref.watch(profileSectionsRepositoryProvider).insert,
);

final profileSectionsRepositoryProvider = Provider<ProfileSectionsRepository>(
  (ref) => ProfileSectionsRepository(ref.watch(supabaseProvider)),
);

final profileSectionsProvider =
    FutureProvider<Map<ProfileSection, List<ProfileEntry>>>((ref) async {
      if (ref.watch(currentUserProvider)?.id == null) return const {};
      return ref.watch(profileSectionsRepositoryProvider).loadAll();
    });

final userSkillsProvider = FutureProvider<List<UserSkill>>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return const [];
  return ref.watch(profileSectionsRepositoryProvider).skills();
});

/// The stage a student is at, in the words the profile uses.
String? _stageLabel(String? stage) => switch (stage) {
  'primary' => 'Primary school',
  'high_school' => 'High school',
  'bachelors' => 'University',
  'graduated' => 'Graduated',
  _ => null,
};

/// Only shown when the student actually gave a result.
String? _gpaLabel(Object? gpa, Object? scale) {
  if (double.tryParse('$gpa') == null) return null;
  final outOf = double.tryParse('$scale');
  if (outOf == null || outOf <= 0) return null;
  return 'GPA $gpa of $scale';
}
