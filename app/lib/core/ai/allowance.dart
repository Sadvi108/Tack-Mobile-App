import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../failure.dart';
import '../supabase/client.dart';

/// What is left of today's shared AI allowance.
///
/// Shared is the important word: the same pool is spent by the coach, by
/// having a CV read properly, by a job-description analysis and by having an
/// interview answer read. It lives in core so every feature reads one
/// provider, rather than each importing the coach's.
class AiAllowance {
  const AiAllowance({required this.used, required this.limit});

  /// Reads the `coach_allowance` row defensively. Anything malformed reads as
  /// nothing left, which is the safe way to be wrong: a student is never told
  /// they have actions the server will refuse.
  factory AiAllowance.fromRow(Map<String, dynamic>? row) {
    int count(Object? value) => value is num && value >= 0 ? value.toInt() : 0;
    return AiAllowance(used: count(row?['used']), limit: count(row?['limit']));
  }

  final int used;

  /// From the server, which defines it once. Never shown to the student: a
  /// screen says what is left, not what the whole allowance is.
  final int limit;

  int get remaining => (limit - used).clamp(0, limit);
  bool get isSpent => remaining == 0;
}

/// The only place the allowance is read from the server.
class AiAllowanceRepository {
  const AiAllowanceRepository(this._db);

  final SupabaseClient _db;

  /// Today's allowance, without spending any of it.
  Future<AiAllowance> current() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('coach_allowance');
      return AiAllowance.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final aiAllowanceRepositoryProvider = Provider<AiAllowanceRepository>(
  (ref) => AiAllowanceRepository(ref.watch(supabaseProvider)),
);

/// Today's shared AI allowance. Invalidate it after anything that may spend
/// an action.
final aiAllowanceProvider = FutureProvider.autoDispose<AiAllowance>((
  ref,
) async {
  if (ref.watch(currentUserProvider)?.id == null) {
    return const AiAllowance(used: 0, limit: 0);
  }
  return ref.watch(aiAllowanceRepositoryProvider).current();
});

/// What is left today, in words. Never the limit.
String allowanceLine(AiAllowance allowance) => switch (allowance.remaining) {
  0 => 'No AI actions left today',
  1 => 'One AI action left today',
  final n => '$n AI actions left today',
};
