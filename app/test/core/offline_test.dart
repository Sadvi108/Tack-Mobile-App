import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';

void main() {
  late LocalDb db;

  setUp(() => db = LocalDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('the outbox keeps offline work', () {
    test('a queued change survives until it is sent', () async {
      await db.enqueue(
        kind: 'task_done',
        targetId: 'task-1',
        payload: jsonEncode({'is_done': true}),
      );

      final pending = await db.pending();
      expect(pending, hasLength(1));
      expect(pending.single.kind, 'task_done');
      expect(jsonDecode(pending.single.payload), {'is_done': true});
    });

    test(
      'ticking the same task five times sends one change, not five',
      () async {
        // A student on a bus with no signal should not generate five writes.
        for (final done in [true, false, true, false, true]) {
          await db.enqueue(
            kind: 'task_done',
            targetId: 'task-1',
            payload: jsonEncode({'is_done': done}),
          );
        }

        final pending = await db.pending();
        expect(pending, hasLength(1));
        expect(
          jsonDecode(pending.single.payload),
          {'is_done': true},
          reason: 'the last change made offline is the one that counts',
        );
      },
    );

    test('different tasks queue separately', () async {
      await db.enqueue(kind: 'task_done', targetId: 'a', payload: '{}');
      await db.enqueue(kind: 'task_done', targetId: 'b', payload: '{}');
      expect(await db.pendingCount(), 2);
    });

    test('different kinds of change on one row queue separately', () async {
      await db.enqueue(
        kind: 'application_status',
        targetId: 'app-1',
        payload: '{}',
      );
      await db.enqueue(
        kind: 'application_notes',
        targetId: 'app-1',
        payload: '{}',
      );
      expect(await db.pendingCount(), 2);
    });

    test('a sent change is discarded', () async {
      final id = await db.enqueue(
        kind: 'task_done',
        targetId: 'task-1',
        payload: '{}',
      );
      await db.discard(id);
      expect(await db.pendingCount(), 0);
    });

    test(
      'failures are counted so a doomed change can be given up on',
      () async {
        final id = await db.enqueue(
          kind: 'task_done',
          targetId: 'task-1',
          payload: '{}',
        );
        await db.bumpAttempts(id, 3, 'no route to host');

        final pending = await db.pending();
        expect(pending.single.attempts, 3);
        expect(pending.single.lastError, 'no route to host');
      },
    );

    test('changes come back oldest first', () async {
      await db.enqueue(kind: 'task_done', targetId: 'first', payload: '{}');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.enqueue(kind: 'task_done', targetId: 'second', payload: '{}');

      final pending = await db.pending();
      expect(pending.map((p) => p.targetId), ['first', 'second']);
    });

    test('the pending count is what the offline state shows', () async {
      expect(await db.pendingCount(), 0);
      await db.enqueue(kind: 'task_done', targetId: 'a', payload: '{}');
      await db.enqueue(
        kind: 'application_status',
        targetId: 'b',
        payload: '{}',
      );
      expect(await db.pendingCount(), 2);
    });
  });

  group('the read cache', () {
    test('what was last seen is available offline', () async {
      await db.putCache('roadmaps', '[{"id":"r1"}]');
      final cached = await db.readCache('roadmaps');
      expect(cached, isNotNull);
      expect(cached!.payload, '[{"id":"r1"}]');
    });

    test('a newer read replaces the older one', () async {
      await db.putCache('roadmaps', 'old');
      await db.putCache('roadmaps', 'new');
      expect((await db.readCache('roadmaps'))!.payload, 'new');
    });

    test('a key never written reads as nothing, not as an error', () async {
      expect(await db.readCache('never-fetched'), isNull);
    });

    test('signing out can clear everything cached', () async {
      await db.putCache('roadmaps', 'x');
      await db.putCache('applications', 'y');
      await db.clearCache();
      expect(await db.readCache('roadmaps'), isNull);
    });
  });
}
