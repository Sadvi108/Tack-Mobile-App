import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/jobs/job_repository.dart';
import '../../../core/supabase/client.dart';
import 'checklist_models.dart';

/// The checklist, the prep brief, and what the checklist's actions need.
class ChecklistRepository {
  const ChecklistRepository(this._db, [this._jobs]);

  final SupabaseClient _db;
  final JobRepository? _jobs;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<Checklist> checklist(String applicationId) async {
    try {
      final result = await _db.rpc(
        'application_checklist',
        params: {'p_application': applicationId},
      );
      return Checklist.fromJson(result);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The newest brief for this application, or null if there is none yet.
  Future<PrepBrief?> latestBrief(String applicationId) async {
    try {
      final row = await _db
          .from('interview_prep_briefs')
          .select('brief')
          .eq('application_id', applicationId)
          .eq('user_id', _uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return PrepBrief.fromJson(row?['brief']);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Asks for a brief and waits for it. A brief built from the same inputs
  /// comes straight back and costs nothing.
  Future<PrepBrief> requestBrief(String applicationId) async {
    try {
      final response = await _db.functions.invoke(
        'interview-prep',
        body: {'applicationId': applicationId},
      );
      final data = response.data;
      if (data is! Map) {
        throw const Failure('The brief could not be started. Try again.');
      }
      final body = data.cast<String, dynamic>();
      final resolved = body['status'] == 'ready' || _jobs == null
          ? body
          : await _jobs.resolve(body);

      if (resolved['skipped'] == 'ungrounded') {
        throw const Failure(
          'There is not enough on your profile to build talking points from yet. '
          'Add your skills and a project, then try again. Your AI action was '
          'returned.',
        );
      }
      final brief = PrepBrief.fromJson(resolved['brief']);
      if (brief == null) {
        throw const Failure('The brief could not be finished. Try again.');
      }
      return brief;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is Map
          ? (details['error'] as Map)['message']
          : null;
      throw Failure(
        message is String
            ? message
            : e.status == 429
            ? 'You have used today\'s AI actions. They reset at midnight.'
            : 'The brief could not be started. Try again.',
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The student's CVs, newest first, for attaching to an application.
  Future<List<CvOption>> cvOptions() async {
    try {
      final rows = await _db
          .from('documents')
          .select('id, title')
          .eq('user_id', _uid)
          .eq('type', 'cv')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return [
        for (final row in rows)
          CvOption(row['id'] as String, (row['title'] as String?) ?? 'CV'),
      ];
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The posting's own description, for checking it from the checklist.
  Future<({String jobId, String? description})> jobOf(
    String applicationId,
  ) async {
    try {
      final row = await _db
          .from('job_applications')
          .select('job_id, jobs(description)')
          .eq('id', applicationId)
          .eq('user_id', _uid)
          .single();
      final job = row['jobs'];
      return (
        jobId: row['job_id'] as String,
        description: job is Map ? job['description'] as String? : null,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final checklistRepositoryProvider = Provider<ChecklistRepository>(
  (ref) => ChecklistRepository(
    ref.watch(supabaseProvider),
    ref.watch(jobRepositoryProvider),
  ),
);
