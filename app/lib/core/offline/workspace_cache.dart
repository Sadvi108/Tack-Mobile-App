import 'dart:convert';
import 'local_db.dart';

/// Remote snapshots and optimistic edits share an account-specific database.
class WorkspaceCache {
  const WorkspaceCache(this.db);
  final LocalDb db;

  Future<List<Map<String, dynamic>>> remember(
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = await _overlay(key, rows);
    await db.putCache(key, jsonEncode(result));
    return result;
  }

  Future<List<Map<String, dynamic>>?> restore(String key) async {
    final cached = await db.readCache(key);
    if (cached == null) return null;
    final rows = (jsonDecode(cached.payload) as List)
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();
    return _overlay(key, rows);
  }

  Future<List<Map<String, dynamic>>> _overlay(
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    final edits = await db.pending(limit: 100000);
    for (final edit in edits) {
      if (key == 'roadmaps' && edit.kind == 'task_done') {
        for (final row in rows) {
          for (final milestone
              in row['roadmap_milestones'] as List? ?? const []) {
            for (final task
                in milestone['roadmap_tasks'] as List? ?? const []) {
              if (task['id'] == edit.targetId) {
                (task as Map).addAll(jsonDecode(edit.payload) as Map);
              }
            }
          }
        }
      } else if (key == 'applications' &&
          edit.kind.startsWith('application_')) {
        for (final row in rows) {
          if (row['id'] == edit.targetId) {
            row.addAll(
              (jsonDecode(edit.payload) as Map).cast<String, dynamic>()
                ..remove('_expected_updated_at'),
            );
          }
        }
      }
    }
    return rows;
  }

  Future<void> queue(
    String cacheKey,
    String kind,
    String id,
    Map<String, Object?> patch,
  ) => db.transaction(() async {
    final previous = (await db.pending(
      limit: 100000,
    )).where((row) => row.kind == kind && row.targetId == id).firstOrNull;
    final snapshot = await restore(cacheKey);
    final target = snapshot?.where((row) => row['id'] == id).firstOrNull;
    final merged = <String, Object?>{
      if (kind == 'application_patch' && target?['updated_at'] != null)
        '_expected_updated_at': target!['updated_at'],
      if (previous != null)
        ...(jsonDecode(previous.payload) as Map).cast<String, Object?>(),
      ...patch,
    };
    await db.enqueue(kind: kind, targetId: id, payload: jsonEncode(merged));
    final rows = await restore(cacheKey);
    if (rows != null) await db.putCache(cacheKey, jsonEncode(rows));
  });
}
