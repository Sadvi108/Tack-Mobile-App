import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import 'readiness.dart';

/// How the student compares with others in their own year.
///
/// Never against final-years. A first-year on 30 is ahead, not behind, and the
/// database view only exposes cohorts of five or more so one student's score
/// can never be inferred from it.
class CohortBenchmark {
  const CohortBenchmark({required this.average, required this.size, required this.mode});

  final int average;
  final int size;
  final YearMode mode;
}

class ScoreRepository {
  const ScoreRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const Failure('You are signed out. Log in and try again.');
    return id;
  }

  Future<ReadinessScore> current() async {
    try {
      final row = await _db
          .from('readiness_scores')
          .select()
          .eq('user_id', _uid)
          .order('computed_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? ReadinessScore.empty : ReadinessScore.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The last 90 days, oldest first, for the trend line.
  Future<List<ReadinessScore>> trend({int days = 90}) async {
    final since = DateTime.now().toUtc().subtract(Duration(days: days));
    try {
      final rows = await _db
          .from('readiness_scores')
          .select()
          .eq('user_id', _uid)
          .gte('computed_at', since.toIso8601String())
          .order('computed_at');
      return rows.map(ReadinessScore.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The change since the most recent snapshot at least seven days old.
  Future<int> weekChange() async {
    final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));
    try {
      final rows = await _db
          .from('readiness_scores')
          .select('total, computed_at')
          .eq('user_id', _uid)
          .order('computed_at', ascending: false)
          .limit(60);
      if (rows.isEmpty) return 0;

      final latest = (rows.first['total'] as num).toInt();
      for (final row in rows) {
        final at = DateTime.tryParse('${row['computed_at']}');
        if (at != null && at.isBefore(weekAgo)) {
          return latest - (row['total'] as num).toInt();
        }
      }
      // No snapshot older than a week: everything so far counts as this week's
      // gain, which is exactly right for a student who joined on Monday.
      return latest - (rows.last['total'] as num).toInt();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<CohortBenchmark?> cohort(YearMode mode, int? yearOfStudy) async {
    if (yearOfStudy == null) return null;
    try {
      final row = await _db
          .from('cohort_benchmarks')
          .select('avg_total, cohort_size')
          .eq('year_of_study', yearOfStudy)
          .eq('mode', mode.name)
          .maybeSingle();
      if (row == null) return null;
      return CohortBenchmark(
        average: (row['avg_total'] as num).toInt(),
        size: (row['cohort_size'] as num).toInt(),
        mode: mode,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The weight table for a mode, so the breakdown can explain that
  /// applications are worth nothing in first year rather than looking broken.
  Future<Map<String, int>> weights(YearMode mode) async {
    try {
      final rows =
          await _db.from('score_weights').select('component, weight').eq('mode', mode.name);
      return {for (final r in rows) r['component'] as String: (r['weight'] as num).toInt()};
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final scoreRepositoryProvider =
    Provider<ScoreRepository>((ref) => ScoreRepository(ref.watch(supabaseProvider)));

final readinessProvider = FutureProvider<ReadinessScore>((ref) async {
  if (!ref.watch(isSignedInProvider)) return ReadinessScore.empty;
  return ref.watch(scoreRepositoryProvider).current();
});

final weekChangeProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(isSignedInProvider)) return 0;
  return ref.watch(scoreRepositoryProvider).weekChange();
});

final scoreTrendProvider = FutureProvider<List<ReadinessScore>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(scoreRepositoryProvider).trend();
});

final cohortProvider = FutureProvider<CohortBenchmark?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  return ref.watch(scoreRepositoryProvider).cohort(profile.mode, profile.yearOfStudy);
});
