import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'coach_models.dart';

/// The only thing that talks to the coach function.
class CoachRepository {
  const CoachRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<CoachReply> ask(String question, {String? threadId}) async {
    try {
      final res = await _db.functions.invoke(
        'coach',
        body: {'question': question, 'threadId': ?threadId},
      );
      final data = res.data;
      if (data is! Map) {
        throw const Failure('The coach could not answer that. Try again.');
      }
      return CoachReply.fromJson(data.cast<String, dynamic>());
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
          .order('created_at');
      return (id, rows.map(ChatMessage.fromRow).toList());
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// How many of today's three are left, without spending one.
  Future<int> remaining() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('coach_allowance');
      final used = (row['used'] as num?)?.toInt() ?? 0;
      final limit = (row['limit'] as num?)?.toInt() ?? 3;
      return (limit - used).clamp(0, limit);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final coachRepositoryProvider = Provider<CoachRepository>(
  (ref) => CoachRepository(ref.watch(supabaseProvider)),
);

final coachHistoryProvider = FutureProvider<(String?, List<ChatMessage>)>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return (null, <ChatMessage>[]);
  return ref.watch(coachRepositoryProvider).latestThread();
});

final coachRemainingProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(isSignedInProvider)) return 0;
  return ref.watch(coachRepositoryProvider).remaining();
});
