import '../../../core/offline/sync.dart';
import '../../../core/offline/workspace_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../../design/tack.dart';
import 'application_models.dart';

class ApplicationRepository {
  const ApplicationRepository(this._db, [this._cache]);
  final WorkspaceCache? _cache;

  final SupabaseClient _db;

  static const _select = '''
    id, job_id, status, applied_at, next_action, next_action_date,
    cv_document_id, notes, updated_at,
    jobs(title, company_name, location, source_url, closes_at, companies(name))
  ''';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<List<JobApplication>> list({TackStatus? status}) async {
    final uid = _uid;
    List<Map<String, dynamic>> rows;
    try {
      rows = await _db
          .from('job_applications')
          .select(_select)
          .eq('user_id', uid)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false);
      if (_uid != uid) {
        throw const Failure(
          'Your account changed. Open your applications again.',
        );
      }
      rows = await _cache?.remember('applications', rows) ?? rows;
    } catch (e) {
      if (!Failure.from(e).isOffline || _uid != uid) throw Failure.from(e);
      final cached = await _cache?.restore('applications');
      if (cached == null) throw Failure.from(e);
      rows = cached;
    }
    return rows
        .map(JobApplication.fromRow)
        .where((row) => status == null || row.status == status)
        .toList();
  }

  Future<ApplicationCounts> counts() async {
    final tally = <TackStatus, int>{};
    for (final row in await list()) {
      tally[row.status] = (tally[row.status] ?? 0) + 1;
    }
    return ApplicationCounts(tally);
  }

  /// Anything due in the next seven days, soonest first. This is the maroon
  /// date card on the final-year dashboard.
  Future<List<JobApplication>> upcoming({int days = 7}) async {
    final today = DateTime.now();
    final until = today.add(Duration(days: days));
    try {
      final rows = await _db
          .from('job_applications')
          .select(_select)
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .not('next_action_date', 'is', null)
          .lte('next_action_date', until.toIso8601String().substring(0, 10))
          .order('next_action_date');
      return rows.map(JobApplication.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<StatusChange>> history(String applicationId) async {
    try {
      final rows = await _db
          .from('application_status_history')
          .select('from_status, to_status, changed_at, note')
          .eq('application_id', applicationId)
          .eq('user_id', _uid)
          .order('changed_at');
      return rows.map(StatusChange.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Creates the job and the application together. Company names are
  /// normalised by the database so "bKash Ltd." and "bkash limited" land on
  /// one company row.
  Future<String> create({
    required String title,
    required String companyName,
    String? location,
    String? sourceUrl,
    DateTime? closesAt,
    TackStatus status = TackStatus.saved,
  }) async {
    try {
      return await _db.rpc<String>(
        'create_application',
        params: {
          'p_title': title.trim(),
          'p_company': companyName.trim(),
          'p_location': location?.trim(),
          'p_source_url': sourceUrl?.trim(),
          'p_closes_at': closesAt?.toIso8601String().substring(0, 10),
          'p_status': status.name,
        },
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Moves an application along. The database validates the transition and the
  /// history row is written by a trigger, so an illegal move fails loudly
  /// rather than silently corrupting the timeline.
  Future<void> setStatus(String applicationId, TackStatus status) =>
      update(applicationId, {'status': status.name});

  Future<void> update(String applicationId, Map<String, Object?> patch) async {
    const fields = {
      'status',
      'notes',
      'next_action',
      'next_action_date',
      'cv_document_id',
      'applied_at',
    };
    if (patch.keys.any((key) => !fields.contains(key))) {
      throw const Failure('That change is not supported.');
    }
    final uid = _uid;
    if (_cache != null) {
      // Persist first; even an app kill between the tap and the request keeps it.
      await _cache.queue(
        'applications',
        'application_patch',
        applicationId,
        patch,
      );
      return;
    }
    try {
      await _db
          .from('job_applications')
          .update(patch)
          .eq('id', applicationId)
          .eq('user_id', uid)
          .select('id')
          .single();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Soft delete. User data is never removed outright.
  Future<void> remove(String applicationId) async {
    try {
      await _db
          .from('job_applications')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', applicationId)
          .eq('user_id', _uid);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final applicationRepositoryProvider = Provider<ApplicationRepository>(
  (ref) => ApplicationRepository(
    ref.watch(supabaseProvider),
    WorkspaceCache(ref.watch(localDbProvider)),
  ),
);

final applicationCountsProvider = FutureProvider<ApplicationCounts>((
  ref,
) async {
  ref.watch(syncRevisionProvider);
  if (ref.watch(currentUserProvider)?.id == null) {
    return ApplicationCounts.empty;
  }
  return ref.watch(applicationRepositoryProvider).counts();
});

final applicationsProvider =
    FutureProvider.family<List<JobApplication>, TackStatus?>((
      ref,
      status,
    ) async {
      ref.watch(syncRevisionProvider);
      if (ref.watch(currentUserProvider)?.id == null) return const [];
      return ref.watch(applicationRepositoryProvider).list(status: status);
    });

final upcomingApplicationsProvider = FutureProvider<List<JobApplication>>((
  ref,
) async {
  ref.watch(syncRevisionProvider);
  if (ref.watch(currentUserProvider)?.id == null) return const [];
  return ref.watch(applicationRepositoryProvider).upcoming();
});
