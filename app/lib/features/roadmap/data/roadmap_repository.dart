import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'roadmap_models.dart';

class RoadmapRepository {
  const RoadmapRepository(this._db);

  final SupabaseClient _db;

  static const _select = '''
    id, title, path_id,
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
    if (id == null) throw const Failure('You are signed out. Log in and try again.');
    return id;
  }

  Future<List<Roadmap>> all() async {
    try {
      final rows = await _db
          .from('roadmaps')
          .select(_select)
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .isFilter('roadmap_tasks.deleted_at', null)
          .order('created_at');
      return rows.map(Roadmap.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Copies a career path template into a roadmap the student owns, so later
  /// edits never mutate the shared template.
  ///
  /// The first milestone opens as active and the rest stay locked; from then
  /// on a database trigger advances them as tasks are ticked.
  Future<String> generateFromPath(String pathId, String title) async {
    try {
      final existing = await _db
          .from('roadmaps')
          .select('id')
          .eq('user_id', _uid)
          .eq('path_id', pathId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;

      final roadmap = await _db
          .from('roadmaps')
          .insert({'user_id': _uid, 'path_id': pathId, 'title': title, 'origin': 'template'})
          .select('id')
          .single();
      final roadmapId = roadmap['id'] as String;

      final templateMilestones = await _db
          .from('career_path_milestones')
          .select('id, order_index, title, description, unlock_text, typical_semester')
          .eq('path_id', pathId)
          .order('order_index');

      final inserted = await _db
          .from('roadmap_milestones')
          .insert([
            for (final m in templateMilestones)
              {
                'roadmap_id': roadmapId,
                'user_id': _uid,
                'source_milestone_id': m['id'],
                'order_index': m['order_index'],
                'title': m['title'],
                'description': m['description'],
                'unlock_text': m['unlock_text'],
                'typical_semester': m['typical_semester'],
                'state': (m['order_index'] as num) == 0 ? 'active' : 'locked',
              },
          ])
          .select('id, source_milestone_id');

      final templateTasks = await _db
          .from('career_path_tasks')
          .select('milestone_id, order_index, title, type, points, est_minutes, skill_id')
          .inFilter(
            'milestone_id',
            [for (final m in templateMilestones) m['id'] as String],
          );

      final byTemplate = {
        for (final m in inserted) m['source_milestone_id'] as String: m['id'] as String,
      };

      await _db.from('roadmap_tasks').insert([
        for (final t in templateTasks)
          if (byTemplate[t['milestone_id'] as String] != null)
            {
              'milestone_id': byTemplate[t['milestone_id'] as String],
              'user_id': _uid,
              'order_index': t['order_index'],
              'title': t['title'],
              'type': t['type'],
              'points': t['points'],
              'est_minutes': t['est_minutes'],
              'skill_id': t['skill_id'],
              'shared_with_roadmaps': [roadmapId],
            },
      ]);

      return roadmapId;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Ticks or un-ticks a task. `done_at` and the milestone state are both set
  /// by database triggers, so this only writes the flag and refetches.
  Future<void> setTaskDone(String taskId, {required bool done}) async {
    try {
      await _db.from('roadmap_tasks').update({'is_done': done}).eq('id', taskId);
    } catch (e) {
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
      await _db.from('roadmap_tasks').update({
        'due_date': due?.toIso8601String().substring(0, 10),
      }).eq('id', taskId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _db
          .from('roadmap_tasks')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', taskId);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final roadmapRepositoryProvider =
    Provider<RoadmapRepository>((ref) => RoadmapRepository(ref.watch(supabaseProvider)));

final roadmapsProvider = FutureProvider<List<Roadmap>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(roadmapRepositoryProvider).all();
});
