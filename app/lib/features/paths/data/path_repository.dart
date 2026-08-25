import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'career_path.dart';

/// A path the student has chosen to follow. At most two at a time — the
/// database enforces the limit with a trigger.
class ChosenPath {
  const ChosenPath({required this.pathId, required this.isPrimary});

  final String pathId;
  final bool isPrimary;
}

class PathRepository {
  const PathRepository(this._db);

  final SupabaseClient _db;

  static const _select = '''
    id, slug, title, summary, category, salary_min_bdt, salary_max_bdt,
    months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order,
    career_path_skills(skill_id, importance, skills(id, name)),
    career_path_milestones(id)
  ''';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const Failure('You are signed out. Log in and try again.');
    return id;
  }

  Future<List<CareerPath>> all() async {
    try {
      final rows = await _db
          .from('career_paths')
          .select(_select)
          .eq('is_active', true)
          .order('sort_order');
      return rows.map(CareerPath.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<CareerPath?> bySlug(String slug) async {
    try {
      final row = await _db.from('career_paths').select(_select).eq('slug', slug).maybeSingle();
      return row == null ? null : CareerPath.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Set<String>> userSkillIds() async {
    try {
      final rows = await _db.from('user_skills').select('skill_id').eq('user_id', _uid);
      return rows.map((r) => r['skill_id'] as String).toSet();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<ChosenPath>> chosen() async {
    try {
      final rows = await _db
          .from('user_career_paths')
          .select('path_id, is_primary')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null);
      return rows
          .map((r) => ChosenPath(
                pathId: r['path_id'] as String,
                isPrimary: r['is_primary'] as bool? ?? false,
              ))
          .toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Follows a path. The two-path limit is enforced by a database trigger; the
  /// error it raises is turned into something a student can act on rather than
  /// a stack trace.
  Future<void> choose(String pathId, {bool primary = false}) async {
    try {
      await _db.from('user_career_paths').upsert(
        {'user_id': _uid, 'path_id': pathId, 'is_primary': primary, 'deleted_at': null},
        onConflict: 'user_id,path_id',
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('at most two career paths')) {
        throw const Failure(
          'You can follow two paths at a time. Drop one before adding another.',
        );
      }
      throw Failure.from(e);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> unfollow(String pathId) async {
    try {
      await _db
          .from('user_career_paths')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', _uid)
          .eq('path_id', pathId);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final pathRepositoryProvider =
    Provider<PathRepository>((ref) => PathRepository(ref.watch(supabaseProvider)));

final careerPathsProvider =
    FutureProvider<List<CareerPath>>((ref) => ref.watch(pathRepositoryProvider).all());

final userSkillIdsProvider = FutureProvider<Set<String>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return <String>{};
  return ref.watch(pathRepositoryProvider).userSkillIds();
});

final chosenPathsProvider = FutureProvider<List<ChosenPath>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(pathRepositoryProvider).chosen();
});

/// Every path with the student's match percentage, best match first.
final pathMatchesProvider = FutureProvider<List<PathMatch>>((ref) async {
  final paths = await ref.watch(careerPathsProvider.future);
  final skills = await ref.watch(userSkillIdsProvider.future);
  final matches = [for (final path in paths) matchPath(path, skills)]
    ..sort((a, b) => b.percent.compareTo(a.percent));
  return matches;
});
