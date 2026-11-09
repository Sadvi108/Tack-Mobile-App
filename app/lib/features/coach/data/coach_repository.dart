import 'dart:math';

import '../../../core/jobs/job_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'coach_models.dart';

/// The only thing that talks to the coach function.
class CoachRepository {
  const CoachRepository(this._db, [this._jobs]);

  final JobRepository? _jobs;

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  /// Asks the coach. Every request carries an `operationId`, which the
  /// server turns into the job's idempotency key: a caller that retries with
  /// the same id gets the same answer and is never charged twice. Without
  /// one, the server fell back to a hash of the text, so asking the same
  /// question again later was treated as a duplicate.
  ///
  /// [onQueued] is called with the job id when the question went to the
  /// model (202), before the wait for its answer begins.
  Future<CoachReply> ask(
    String question, {
    String? threadId,
    String? operationId,
    void Function(String jobId)? onQueued,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'coach',
        body: {
          'question': question,
          'threadId': ?threadId,
          'operationId': operationId ?? newOperationId(),
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw const Failure('The coach could not answer that. Try again.');
      }
      if (data['jobId'] case final String jobId) onQueued?.call(jobId);
      final reply =
          await _jobs?.resolve(data.cast<String, dynamic>()) ??
          data.cast<String, dynamic>();
      return CoachReply.fromJson(reply);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The most recent conversation, oldest message first.
  Future<(String?, List<ChatMessage>)> latestThread() async {
    try {
      final thread = await _db
          .from('chat_threads')
          .select('id')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (thread == null) return (null, <ChatMessage>[]);

      final id = thread['id'] as String;
      final rows = await _db
          .from('chat_messages')
          .select()
          .eq('thread_id', id)
          .eq('user_id', _uid)
          .order('created_at', ascending: true);
      return (id, rows.map(ChatMessage.fromRow).toList());
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

/// A random (version 4) UUID, which is what the server's request schema
/// accepts as an `operationId`. A caller keeps it to retry the same question.
/// Small enough not to need a package for.
String newOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

final coachRepositoryProvider = Provider<CoachRepository>(
  (ref) => CoachRepository(
    ref.watch(supabaseProvider),
    ref.watch(jobRepositoryProvider),
  ),
);

/// The latest conversation. Disposed when nobody is watching, so reopening
/// the coach reads it again instead of showing the copy from the last visit,
/// which left out every reply that arrived since.
final coachHistoryProvider =
    FutureProvider.autoDispose<(String?, List<ChatMessage>)>((ref) async {
      if (ref.watch(currentUserProvider)?.id == null) {
        return (null, <ChatMessage>[]);
      }
      return ref.watch(coachRepositoryProvider).latestThread();
    });
