import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import 'local_db.dart';

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb(null, ref.watch(currentUserProvider)?.id ?? 'signed_out');
  ref.onDispose(db.close);
  return db;
});

/// Whether the device currently has a route to the network.
///
/// Not a promise that requests will succeed — a captive portal or a dead
/// tower still reports a connection — so a failed write is queued rather than
/// treated as an error.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield !(await connectivity.checkConnectivity()).contains(
    ConnectivityResult.none,
  );
  yield* connectivity.onConnectivityChanged.map(
    (results) => !results.contains(ConnectivityResult.none),
  );
});

final isOnlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider).value ?? true,
);

/// How many changes are waiting to sync. Shown in the offline state so the
/// student can see nothing has been lost.
final pendingChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(localDbProvider).watchPendingCount(),
);

/// Sends queued changes when the network comes back.
///
/// Every change is idempotent: setting a task's done flag or an application's
/// status twice produces the same row, so replaying a change that actually
/// succeeded before the connection dropped is harmless.
class SyncService {
  SyncService(this._ref);

  final Ref _ref;
  bool _running = false;

  Future<int> flush() async {
    if (_running) return 0;
    _running = true;

    final db = _ref.read(localDbProvider);
    final client = _ref.read(supabaseProvider);
    var sent = 0;

    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null || db.accountId != userId) return 0;
      while (client.auth.currentUser?.id == userId) {
        final items = await db.pending();
        if (items.isEmpty) break;
        var failed = false;
        for (final item in items) {
          if (client.auth.currentUser?.id != userId) return sent;
          try {
            await _apply(client, userId, item);
            if (client.auth.currentUser?.id != userId) return sent;
            await db.discard(item.id);
            sent++;
          } catch (error) {
            if (client.auth.currentUser?.id != userId) return sent;
            await db.bumpAttempts(
              item.id,
              item.attempts + 1,
              error is PostgrestException &&
                      error.message.contains('sync_conflict')
                  ? 'sync_conflict'
                  : 'sync_pending',
            );
            failed = true;
          }
        }
        // Keep failed work visible. A later reconnect/resume retries it.
        if (failed) break;
      }
      if (sent > 0) _ref.read(syncRevisionProvider.notifier).changed();
    } finally {
      _running = false;
    }

    return sent;
  }

  Future<Map<String, dynamic>> currentApplication(String id) async {
    final client = _ref.read(supabaseProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('sign_in_required');
    return await client
        .from('job_applications')
        .select('notes,status,next_action,next_action_date,updated_at')
        .eq('id', id)
        .eq('user_id', uid)
        .single();
  }

  Future<void> resolveConflict(
    OutboxData item, {
    required bool keepLocal,
    String? expectedVersion,
  }) async {
    final db = _ref.read(localDbProvider);
    if (db.accountId != _ref.read(supabaseProvider).auth.currentUser?.id) {
      return;
    }
    if (keepLocal) {
      final payload = (jsonDecode(item.payload) as Map).cast<String, dynamic>();
      payload['_expected_updated_at'] = expectedVersion;
      await db.enqueue(
        kind: item.kind,
        targetId: item.targetId,
        payload: jsonEncode(payload),
      );
    } else {
      await db.discard(item.id);
      // Drop the optimistic snapshot so it cannot reappear after discarding.
      await db.clearCache();
    }
    _ref.read(syncRevisionProvider.notifier).changed();
    await flush();
  }

  Future<void> _apply(
    SupabaseClient client,
    String userId,
    OutboxData item,
  ) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    List<Map<String, dynamic>> rows;
    switch (item.kind) {
      case 'task_done':
        rows = await client
            .from('roadmap_tasks')
            .update({'is_done': payload['is_done']})
            .eq('id', item.targetId)
            .eq('user_id', userId)
            .select('id');
      case 'application_status':
        rows = await client
            .from('job_applications')
            .update({'status': payload['status']})
            .eq('id', item.targetId)
            .eq('user_id', userId)
            .select('id');
      case 'application_notes':
        rows = await client
            .from('job_applications')
            .update({'notes': payload['notes']})
            .eq('id', item.targetId)
            .eq('user_id', userId)
            .select('id');
      case 'application_patch':
        final expected = payload.remove('_expected_updated_at');
        final id = await client.rpc<String>(
          'apply_application_patch',
          params: {
            'p_id': item.targetId,
            'p_patch': payload,
            'p_expected_updated_at': expected,
          },
        );
        rows = [
          {'id': id},
        ];
      default:
        throw StateError('unknown queued change');
    }
    if (rows.length != 1) throw StateError('sync_target_unavailable');
  }
}

final syncServiceProvider = Provider<SyncService>(SyncService.new);

class SyncRevision extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final syncRevisionProvider = NotifierProvider<SyncRevision, int>(
  SyncRevision.new,
);

/// Drain on a connected cold start, reauthentication, reconnect and resume.
final syncOnReconnectProvider = Provider<void>((ref) {
  void flush() {
    if (ref.read(isOnlineProvider)) {
      unawaited(ref.read(syncServiceProvider).flush());
    }
  }

  ref.listen(connectivityProvider, (_, next) {
    if (next.value == true) flush();
  });
  ref.listen(pendingChangesProvider, (_, next) {
    if ((next.value ?? 0) > 0) flush();
  });
  ref.listen(currentUserProvider, (_, next) {
    if (next != null) flush();
  });
  final lifecycle = AppLifecycleListener(onResume: flush);
  ref.onDispose(lifecycle.dispose);
  Future.microtask(flush);
});

final syncProblemsProvider = StreamProvider<List<OutboxData>>(
  (ref) => ref.watch(localDbProvider).watchProblems(),
);
