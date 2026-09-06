import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'analysis_models.dart';

/// Talks to the analyser Edge Function.
///
/// The model key lives on the server. This class knows an endpoint name and
/// nothing about which provider is behind it.
class AnalysisRepository {
  const AnalysisRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<AnalysisState> submit(String text) async {
    try {
      final response = await _db.functions.invoke(
        'analyze-jd',
        body: {'text': text},
      );
      final body = (response.data as Map?)?.cast<String, dynamic>() ?? const {};

      if (response.status == 429) {
        return AnalysisFailed(
          _errorMessage(body) ??
              'You have used today\'s AI actions. They reset at midnight.',
          quotaExhausted: true,
        );
      }
      if (response.status >= 400) {
        return AnalysisFailed(
          _errorMessage(body) ?? 'That did not work. Try again in a moment.',
        );
      }

      if (body['status'] == 'ready') {
        return AnalysisReady(
          JdAnalysis.fromJson(
            body['analysisId'] as String,
            (body['extracted'] as Map).cast<String, dynamic>(),
          ),
          JdMatch.fromJson((body['match'] as Map).cast<String, dynamic>()),
          cached: body['cached'] == true,
        );
      }

      return AnalysisQueued(body['jobId'] as String?);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<String?> latestJob() async {
    final row = await _db
        .from('jobs_queue')
        .select('id')
        .eq('user_id', _uid)
        .eq('type', 'analyse_jd')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Polls a queued job. Returns null while it is still running.
  Future<AnalysisState?> poll(String jobId) async {
    try {
      final job = await _db
          .from('jobs_queue')
          .select('status, result, last_error')
          .eq('id', jobId)
          .eq('user_id', _uid)
          .maybeSingle();
      if (job == null) return null;

      switch (job['status'] as String?) {
        case 'done':
          final result = (job['result'] as Map?)?.cast<String, dynamic>();
          final analysisId = result?['analysisId'] as String?;
          if (analysisId == null) return null;
          return await fetchResult(analysisId);
        case 'dead':
          return AnalysisFailed(
            'That analysis did not finish. Your quota has not been used again — try once more.',
          );
        default:
          return null;
      }
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<AnalysisState?> fetchResult(String analysisId) async {
    try {
      final analysis = await _db
          .from('job_analyses')
          .select('id, extracted')
          .eq('id', analysisId)
          .maybeSingle();
      final match = await _db
          .from('job_match_scores')
          .select('match_percent, matched_skills, missing_skills')
          .eq('analysis_id', analysisId)
          .eq('user_id', _uid)
          .maybeSingle();
      if (analysis == null) return null;

      return AnalysisReady(
        JdAnalysis.fromJson(
          analysis['id'] as String,
          (analysis['extracted'] as Map).cast<String, dynamic>(),
        ),
        match == null
            ? JdMatch.empty
            : JdMatch.fromJson(match.cast<String, dynamic>()),
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Adds the skills a job wanted and the student does not have to the roadmap
  /// they are already following.
  Future<int> addMissingSkillsToRoadmap(List<String> missing) async {
    if (missing.isEmpty) return 0;
    try {
      final roadmap = await _db
          .from('roadmaps')
          .select('id')
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (roadmap == null) {
        throw const Failure(
          'Follow a career path first, then missing skills can be added to its roadmap.',
        );
      }

      final milestone = await _db
          .from('roadmap_milestones')
          .select('id')
          .eq('roadmap_id', roadmap['id'] as String)
          .eq('state', 'active')
          .order('order_index')
          .limit(1)
          .maybeSingle();
      if (milestone == null) {
        throw const Failure(
          'There is no open milestone to add these to right now.',
        );
      }

      await _db.from('roadmap_tasks').insert([
        for (final skill in missing.take(6))
          {
            'milestone_id': milestone['id'],
            'user_id': _uid,
            'title': 'Learn $skill',
            'type': 'skill',
            'points': 3,
            'is_custom': true,
          },
      ]);

      return missing.take(6).length;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  static String? _errorMessage(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    return null;
  }
}

final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepository(ref.watch(supabaseProvider)),
);

/// Deliberately gone: the analyser used to count its own allowance against
/// bucket `ai_actions` with a local `dailyQuota = 3`, while the coach counted
/// `ai` and the database enforced something else again. Watch
/// `aiAllowanceProvider` instead — one pool, one number, read from the server.
