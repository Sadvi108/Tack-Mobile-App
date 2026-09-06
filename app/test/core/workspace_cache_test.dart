import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/workspace_cache.dart';

void main() {
  test(
    'edits merge durably and retain their original conflict timestamp',
    () async {
      final db = LocalDb(NativeDatabase.memory(), 'account-a');
      addTearDown(db.close);
      final cache = WorkspaceCache(db);
      await cache.remember('applications', [
        {
          'id': 'a',
          'notes': 'before',
          'status': 'saved',
          'updated_at': '2026-09-06T00:00:00Z',
        },
      ]);
      await cache.queue('applications', 'application_patch', 'a', {
        'notes': 'after',
      });
      await cache.queue('applications', 'application_patch', 'a', {
        'status': 'applied',
      });
      final edit = (await db.pending()).single;
      expect(jsonDecode(edit.payload), {
        'notes': 'after',
        'status': 'applied',
        '_expected_updated_at': '2026-09-06T00:00:00Z',
      });
      final visible = (await cache.restore('applications'))!.single;
      expect(visible['notes'], 'after');
      expect(visible['status'], 'applied');
      // A stale remote refresh cannot hide pending changes.
      expect(
        (await cache.remember('applications', [
          {'id': 'a', 'notes': 'before'},
        ])).single['notes'],
        'after',
      );
    },
  );
  test(
    'accounts and a backlog larger than a single flush stay separate',
    () async {
      final a = LocalDb(NativeDatabase.memory(), 'a');
      final b = LocalDb(NativeDatabase.memory(), 'b');
      addTearDown(a.close);
      addTearDown(b.close);
      for (var i = 0; i < 75; i++) {
        await a.enqueue(kind: 'task_done', targetId: '$i', payload: '{}');
      }
      expect(await b.pendingCount(), 0);
      var drained = 0;
      while ((await a.pending()).isNotEmpty) {
        for (final item in await a.pending()) {
          await a.discard(item.id);
          drained++;
        }
      }
      expect(drained, 75);
    },
  );
}
