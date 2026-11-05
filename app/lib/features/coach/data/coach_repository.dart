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
  Future<CoachReply> ask(
    String question, {
    String? threadId,
    String? operationId,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'coach',
        body: {
          'question': question,
          'threadId': ?threadId,
          'operationId': operationId ?? _operationId(),
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw const Failure('The coach could not answer that. Try again.');
      }
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

  /// Today's allowance, without spending any of it.
  ///
  /// The limit comes from the server. It used to be read and thrown away while
  /// the screen printed a hardcoded 3, so raising it in the database would
  /// have left the app confidently telling students the wrong number.
  Future<AiAllowance> allowance() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('coach_allowance');
      return AiAllowance(
        used: (row['used'] as num?)?.toInt() ?? 0,
        limit: (row['limit'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

/// A random (version 4) UUID, which is what the server's request schema
/// accepts as an `operationId`. Small enough not to need a package for.
String _operationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// What is left of today's shared AI allowance.
///
/// Shared is the important word: the same pool is spent by the coach, by
/// having a CV read properly, by a job-description analysis and by having an
/// interview answer read. It was only ever shown on the coach screen, labelled
/// "coach questions", so a student who spent it elsewhere found the coach
/// empty with no explanation.
class AiAllowance {
  const AiAllowance({required this.used, required this.limit});

  final int used;
  final int limit;

  int get remaining => (limit - used).clamp(0, limit);
  bool get isSpent => remaining == 0;
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

/// Today's shared AI allowance. Watched anywhere an action might be spent,
/// not only by the coach.
final aiAllowanceProvider = FutureProvider<AiAllowance>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) {
    return const AiAllowance(used: 0, limit: 0);
  }
  return ref.watch(coachRepositoryProvider).allowance();
});
