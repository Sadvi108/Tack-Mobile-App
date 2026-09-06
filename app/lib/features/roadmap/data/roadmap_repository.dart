import '../../../core/offline/sync.dart';
import '../../../core/offline/workspace_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'path_suggestion.dart';
import 'roadmap_models.dart';

class RoadmapRepository {
  const RoadmapRepository(this._db, [this._cache]);
  final WorkspaceCache? _cache;

  final SupabaseClient _db;

  static const _select = '''
    id, title, path_id, skipped_count,
    career_paths(slug),
    roadmap_milestones(
      id, roadmap_id, order_index, title, description, unlock_text, typical_semester, state,
      roadmap_tasks(
        id, milestone_id, order_index, title, type, points, est_minutes,
        due_date, is_done, is_custom, shared_with_roadmaps
      )
    )
  ''';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<List<Roadmap>> all() async {
    final uid = _uid;
    try {
      final rows = await _db
          .from('roadmaps')
          .select(_select)
          .eq('user_id', uid)
          .isFilter('deleted_at', null)
          // The full path, because roadmap_tasks is nested inside
          // roadmap_milestones. Filtering it as a top-level embed made
          // PostgREST answer 400 on every call — "'roadmap_tasks' is not an
          // embedded resource in this request" — so the roadmap list has
          // never loaded for anyone. The dashboard read it as
          // `.value ?? const []`, which turned a hard failure into an empty
          // screen nobody could see was broken.
          .isFilter('roadmap_milestones.roadmap_tasks.deleted_at', null)
          .order('created_at');
      if (_uid != uid) {
        throw const Failure('Your account changed. Open your roadmap again.');
      }
      final visible = await _cache?.remember('roadmaps', rows) ?? rows;
      return visible.map(Roadmap.fromRow).toList();
    } catch (e) {
      if (Failure.from(e).isOffline && _uid == uid) {
        final cached = await _cache?.restore('roadmaps');
        if (cached != null) return cached.map(Roadmap.fromRow).toList();
      }
      throw Failure.from(e);
    }
  }

  /// Builds a roadmap for this student from a career path template.
  ///
  /// One call. This used to be four sequential round trips with no transaction
  /// around them — insert the roadmap, read the template milestones, insert
  /// them, read the template tasks, insert those — and a phone that lost the
  /// connection partway left a roadmaps row with nothing underneath it. The
  /// idempotency guard then found that shell and returned it forever, so the
  /// student could never generate the roadmap again and the screen read "0 of
  /// 0 steps done" with no way back. One such roadmap was found in production.
  ///
  /// The database also does the part this could never do: it knows which
  /// skills the student already has, and when they graduate, so the roadmap it
  /// returns is shaped for them rather than being a copy of the template.
  /// The title is no longer passed: the function reads it from the path row,
  /// so the roadmap cannot be named something the path is not called.
  Future<String> generateFromPath(String pathId) async {
    try {
      return await _db.rpc<String>(
        'generate_roadmap',
        params: {'p_path_id': pathId},
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Stops following a path, retiring its roadmap with it.
  ///
  /// Nothing is destroyed. The roadmap is soft-deleted by a trigger and every
  /// ticked step survives, so following the path again restores it exactly as
  /// it was. That is what makes this safe to offer as a button.
  Future<void> stopFollowing(String pathId) async {
    try {
      await _db.rpc<bool>('stop_following_path', params: {'p_path_id': pathId});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Reads the student and ranks the paths that fit them.
  Future<PathAdvice> advice() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('path_suggestions');
      return PathAdvice.fromJson(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Ticks or un-ticks a task. `done_at` and the milestone state are both set
  /// by database triggers, so this only writes the flag and refetches.
  Future<void> setTaskDone(String taskId, {required bool done}) async {
    if (_cache != null) {
      await _cache.queue('roadmaps', 'task_done', taskId, {'is_done': done});
      return;
    }
    final uid = _uid;
    try {
      await _db
          .from('roadmap_tasks')
          .update({'is_done': done})
          .eq('id', taskId)
          .eq('user_id', uid)
          .select('id')
          .single();
    } catch (e) {
      if (Failure.from(e).isOffline && _cache != null && _uid == uid) {
        await _cache.queue('roadmaps', 'task_done', taskId, {'is_done': done});
        return;
      }
      throw Failure.from(e);
    }
  }

  Future<void> addCustomTask({
    required String milestoneId,
    required String title,
    TaskType type = TaskType.skill,
    DateTime? dueDate,
  }) async {
    try {
      final last = await _db
          .from('roadmap_tasks')
          .select('order_index')
          .eq('milestone_id', milestoneId)
          .order('order_index', ascending: false)
          .limit(1)
          .maybeSingle();

      await _db.from('roadmap_tasks').insert({
        'milestone_id': milestoneId,
        'user_id': _uid,
        'order_index': ((last?['order_index'] as num?)?.toInt() ?? -1) + 1,
        'title': title.trim(),
        'type': type.name,
        'points': 2,
        'is_custom': true,
        'due_date': dueDate?.toIso8601String().substring(0, 10),
      });
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> setTaskDue(String taskId, DateTime? due) async {
    try {
      await _db
          .from('roadmap_tasks')
          .update({'due_date': due?.toIso8601String().substring(0, 10)})
          .eq('id', taskId)
          .eq('user_id', _uid);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _db
          .from('roadmap_tasks')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', taskId)
          .eq('user_id', _uid);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

/// What Tack reads out of the student's own answers, and where it thinks they
/// could go as a result.
final pathAdviceProvider = FutureProvider<PathAdvice>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return PathAdvice.empty;
  return ref.watch(roadmapRepositoryProvider).advice();
});

final roadmapRepositoryProvider = Provider<RoadmapRepository>(
  (ref) => RoadmapRepository(
    ref.watch(supabaseProvider),
    WorkspaceCache(ref.watch(localDbProvider)),
  ),
);

final roadmapsProvider = FutureProvider<List<Roadmap>>((ref) async {
  ref.watch(syncRevisionProvider);
  if (ref.watch(currentUserProvider)?.id == null) return const [];
  return ref.watch(roadmapRepositoryProvider).all();
});
