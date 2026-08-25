import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../../design/tack.dart';
import 'application_models.dart';

class ApplicationRepository {
  const ApplicationRepository(this._db);

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
    try {
      var query = _db
          .from('job_applications')
          .select(_select)
          .eq('user_id', _uid)
          .isFilter('deleted_at', null);
      if (status != null) query = query.eq('status', status.name);

      final rows = await query.order('updated_at', ascending: false);
      return rows.map(JobApplication.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<ApplicationCounts> counts() async {
    try {
      final rows = await _db
          .from('job_applications')
          .select('status')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null);

      final tally = <TackStatus, int>{};
      for (final row in rows) {
        final status = TackStatusStyle.fromWire('${row['status']}');
        tally[status] = (tally[status] ?? 0) + 1;
      }
      return ApplicationCounts(tally);
    } catch (e) {
      throw Failure.from(e);
    }
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
      final companyId = companyName.trim().isEmpty
          ? null
          : await _db.rpc<String?>(
              'upsert_company',
              params: {'raw_name': companyName.trim()},
            );

      final job = await _db
          .from('jobs')
          .insert({
            'user_id': _uid,
            'company_id': companyId,
            'company_name': companyName.trim(),
            'title': title.trim(),
            'location': location?.trim(),
            'source_url': sourceUrl?.trim(),
            'closes_at': closesAt?.toIso8601String().substring(0, 10),
          })
          .select('id')
          .single();

      final application = await _db
          .from('job_applications')
          .insert({'user_id': _uid, 'job_id': job['id'], 'status': status.name})
          .select('id')
          .single();

      return application['id'] as String;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Moves an application along. The database validates the transition and the
  /// history row is written by a trigger, so an illegal move fails loudly
  /// rather than silently corrupting the timeline.
  Future<void> setStatus(String applicationId, TackStatus status) async {
    try {
      await _db
          .from('job_applications')
          .update({'status': status.name})
          .eq('id', applicationId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> update(String applicationId, Map<String, Object?> patch) async {
    try {
      await _db.from('job_applications').update(patch).eq('id', applicationId);
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
          .eq('id', applicationId);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final applicationRepositoryProvider = Provider<ApplicationRepository>(
  (ref) => ApplicationRepository(ref.watch(supabaseProvider)),
);

final applicationCountsProvider = FutureProvider<ApplicationCounts>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return ApplicationCounts.empty;
  return ref.watch(applicationRepositoryProvider).counts();
});

final applicationsProvider =
    FutureProvider.family<List<JobApplication>, TackStatus?>((
      ref,
      status,
    ) async {
      if (!ref.watch(isSignedInProvider)) return const [];
      return ref.watch(applicationRepositoryProvider).list(status: status);
    });

final upcomingApplicationsProvider = FutureProvider<List<JobApplication>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(applicationRepositoryProvider).upcoming();
});
