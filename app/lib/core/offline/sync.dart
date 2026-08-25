import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import 'local_db.dart';

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
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

  static const _maxAttempts = 5;

  Future<int> flush() async {
    if (_running) return 0;
    _running = true;

    final db = _ref.read(localDbProvider);
    final client = _ref.read(supabaseProvider);
    var sent = 0;

    try {
      if (client.auth.currentUser == null) return 0;

      for (final item in await db.pending()) {
        try {
          await _apply(client, item);
          await db.discard(item.id);
          sent++;
        } catch (e) {
          final attempts = item.attempts + 1;
          if (attempts >= _maxAttempts) {
            // Five failures is not a connection problem. Drop it rather than
            // retrying for ever against a change the server will never accept.
            await db.discard(item.id);
          } else {
            await db.bumpAttempts(item.id, attempts, e.toString());
          }
        }
      }
    } finally {
      _running = false;
    }

    return sent;
  }

  Future<void> _apply(SupabaseClient client, OutboxData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    switch (item.kind) {
      case 'task_done':
        await client
            .from('roadmap_tasks')
            .update({'is_done': payload['is_done']})
            .eq('id', item.targetId);
      case 'application_status':
        await client
            .from('job_applications')
            .update({'status': payload['status']})
            .eq('id', item.targetId);
      case 'application_notes':
        await client
            .from('job_applications')
            .update({'notes': payload['notes']})
            .eq('id', item.targetId);
      default:
        throw StateError('unknown queued change: ${item.kind}');
    }
  }
}

final syncServiceProvider = Provider<SyncService>(SyncService.new);

/// Flushes the queue whenever the device comes back online.
final syncOnReconnectProvider = Provider<void>((ref) {
  ref.listen(connectivityProvider, (previous, next) {
    final wasOffline = previous?.value == false;
    final isOnline = next.value == true;
    if (wasOffline && isOnline) {
      unawaited(ref.read(syncServiceProvider).flush());
    }
  });
});
