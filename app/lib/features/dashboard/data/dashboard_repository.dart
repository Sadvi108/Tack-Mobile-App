import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'dashboard_feed.dart';

/// The only thing that calls `dashboard_feed`.
///
/// One RPC replaces the nine reads the home screen used to make. The function
/// derives the student from `auth.uid()`, so there is no user id to pass and
/// no way for this repository to ask about anyone else — which is the point of
/// it being a function rather than nine table reads.
class DashboardRepository {
  const DashboardRepository(this._db);

  final SupabaseClient _db;

  /// Null when the account exists but onboarding has not written a profile
  /// yet. That is a state, not a failure, and the screen shows setup rather
  /// than an error.
  Future<DashboardFeed?> feed() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>?>('dashboard_feed');
      if (row == null) return null;
      return DashboardFeed.fromJson(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseProvider)),
);

/// The single source the home screen reads.
///
/// Widget tests override this one provider instead of the thirteen the screen
/// used to compose, which is most of why the dashboard is now testable without
/// a network stub per card.
final dashboardFeedProvider = FutureProvider<DashboardFeed?>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return null;
  return ref.watch(dashboardRepositoryProvider).feed();
});
