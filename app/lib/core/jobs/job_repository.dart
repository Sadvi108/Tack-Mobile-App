import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../failure.dart';
import '../offline/local_db.dart';
import '../offline/sync.dart';
import '../supabase/client.dart';

/// Durable job receipts are partitioned by the account that submitted them.
class JobRepository {
  const JobRepository(this._client, this._local);
  final SupabaseClient _client;
  final LocalDb _local;

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> response) async {
    final id = response['jobId'];
    if (id is! String) return response;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const Failure('Sign in to check your request.');
    await _local.putCache('user:$userId:job:$id', jsonEncode(response));
    final until = DateTime.now().add(const Duration(minutes: 12));
    while (DateTime.now().isBefore(until)) {
      if (_client.auth.currentUser?.id != userId) {
        throw const Failure(
          'Sign in to the same account to check your request.',
        );
      }
      Map<String, dynamic>? job;
      try {
        job = await _client
            .from('jobs_queue')
            .select('status, result')
            .eq('id', id)
            .eq('user_id', userId)
            .maybeSingle();
      } on AuthException {
        rethrow;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      if (job == null) {
        throw const Failure('That request is no longer available.');
      }
      if (job['status'] == 'dead') {
        throw const Failure(
          'That request could not finish. Its AI action was returned. Try again.',
        );
      }
      final result = job['result'];
      if (job['status'] == 'done' && result is Map) {
        return {...response, ...result.cast<String, dynamic>()};
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw const Failure(
      'Your request is still saved. Come back shortly to check it.',
    );
  }
}

final jobRepositoryProvider = Provider<JobRepository>(
  (ref) =>
      JobRepository(ref.watch(supabaseProvider), ref.watch(localDbProvider)),
);
