import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/workspace_cache.dart';
import 'package:tack/features/roadmap/data/roadmap_repository.dart';

void main() {
  // A tick is written to this phone's queue first and synced from there. That
  // is a real save, so it completes as a success: the student is never shown
  // an offline failure for it, and the queued sentence is not needed.
  test('a tick kept on this phone completes and waits in the queue', () async {
    final db = LocalDb(NativeDatabase.memory(), 'account-a');
    addTearDown(db.close);
    final repository = RoadmapRepository(
      SupabaseClient(
        'http://localhost',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      WorkspaceCache(db),
    );

    await expectLater(repository.setTaskDone('task-1', done: true), completes);

    final queued = (await db.pending()).single;
    expect(queued.kind, 'task_done');
    expect(queued.targetId, 'task-1');
    expect(jsonDecode(queued.payload), {'is_done': true});
  });
}
