import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'interview_models.dart';

class InterviewRepository {
  const InterviewRepository(this._db);

  final SupabaseClient _db;

  static const _select = '''
    id, role, session_type, difficulty, timer_enabled, completed_at,
    overall_score, strongest_area, weakest_area, points_earned,
    interview_questions(
      id, order_index, question, category, answer_text, skipped,
      interview_feedback(score, went_well, to_improve, model_answer)
    )
  ''';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<List<InterviewSession>> history({int limit = 10}) async {
    try {
      final rows = await _db
          .from('interview_sessions')
          .select(_select)
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .order('started_at', ascending: false)
          .limit(limit);
      return rows.map(InterviewSession.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<InterviewSession?> byId(String id) async {
    try {
      final row = await _db
          .from('interview_sessions')
          .select(_select)
          .eq('id', id)
          .eq('user_id', _uid)
          .maybeSingle();
      return row == null ? null : InterviewSession.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The employers students actually apply to, and what each is known to ask.
  ///
  /// Seeded reference data, readable by any signed-in student. No model is
  /// involved at any point.
  Future<List<CompanyPack>> companyPacks() async {
    try {
      final rows = await _db
          .from('company_interview_packs')
          .select('slug, name, about, questions')
          .order('name');
      return rows.map(CompanyPack.fromRow).toList(growable: false);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Starts a session from a company pack.
  ///
  /// Written straight into the tables rather than through the Edge Function:
  /// the questions are already here, so a round trip to a server whose only
  /// job would be to hand them back is a round trip for nothing. It also means
  /// this works with no quota and no network beyond the insert.
  Future<InterviewSession> startFromPack({
    required CompanyPack pack,
    required bool timerEnabled,
  }) async {
    try {
      final session = await _db
          .from('interview_sessions')
          .insert({
            'user_id': _uid,
            'role': pack.name,
            'session_type': InterviewType.mixed.name,
            'difficulty': Difficulty.medium.name,
            'timer_enabled': timerEnabled,
            'question_count': pack.questions.length,
          })
          .select('id')
          .single();

      final sessionId = session['id'] as String;

      await _db.from('interview_questions').insert([
        for (var i = 0; i < pack.questions.length; i++)
          {
            'session_id': sessionId,
            'user_id': _uid,
            'order_index': i,
            'question': pack.questions[i],
            'category': 'company',
          },
      ]);

      final created = await byId(sessionId);
      if (created == null) {
        throw const Failure('The session could not be opened.');
      }
      return created;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Starts a session. Question sets are cached server-side by role, type and
  /// difficulty, so a repeat setup usually costs no quota at all.
  Future<InterviewSession> start({
    required String role,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timerEnabled,
    int count = 5,
  }) async {
    try {
      final response = await _db.functions.invoke(
        'interview/questions',
        body: {
          'role': role,
          'sessionType': type.name,
          'difficulty': difficulty.name,
          'count': count,
        },
      );

      final body = (response.data as Map?)?.cast<String, dynamic>() ?? const {};
      if (response.status >= 400) {
        final error = body['error'];
        throw Failure(
          error is Map && error['message'] is String
              ? error['message'] as String
              : 'Questions could not be prepared. Try again in a moment.',
        );
      }

      final questions = (body['questions'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();
      if (questions.isEmpty) {
        throw const Failure('No questions came back. Try a different role.');
      }

      final session = await _db
          .from('interview_sessions')
          .insert({
            'user_id': _uid,
            'role': role,
            'session_type': type.name,
            'difficulty': difficulty.name,
            'timer_enabled': timerEnabled,
            'question_count': questions.length,
          })
          .select('id')
          .single();

      final sessionId = session['id'] as String;

      await _db.from('interview_questions').insert([
        for (var i = 0; i < questions.length; i++)
          {
            'session_id': sessionId,
            'user_id': _uid,
            'order_index': i,
            'question': questions[i]['question'],
            'category': questions[i]['category'],
          },
      ]);

      final created = await byId(sessionId);
      if (created == null) {
        throw const Failure('The session could not be opened.');
      }
      return created;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<AnswerFeedback> submitAnswer({
    required String questionId,
    required String answer,
  }) async {
    try {
      final response = await _db.functions.invoke(
        'interview/evaluate',
        body: {'questionId': questionId, 'answer': answer},
      );
      final body = (response.data as Map?)?.cast<String, dynamic>() ?? const {};

      if (response.status >= 400) {
        final error = body['error'];
        throw Failure(
          error is Map && error['message'] is String
              ? error['message'] as String
              : 'That answer could not be reviewed. Try again in a moment.',
        );
      }

      return AnswerFeedback.fromJson(
        (body['feedback'] as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> skip(String questionId) async {
    try {
      await _db
          .from('interview_questions')
          .update({
            'skipped': true,
            'answered_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', questionId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Closes the session and records the summary. Points are awarded for
  /// finishing, because finishing is the behaviour worth encouraging.
  Future<InterviewSession> complete(InterviewSession session) async {
    try {
      final average = session.averageScore;
      final scored = session.questions
          .where((q) => q.feedback != null && !q.skipped)
          .toList();

      String? strongest;
      String? weakest;
      if (scored.isNotEmpty) {
        final sorted = [...scored]
          ..sort((a, b) => b.feedback!.score.compareTo(a.feedback!.score));
        strongest = sorted.first.category ?? 'your examples';
        weakest = sorted.last.category ?? 'your structure';
      }

      await _db
          .from('interview_sessions')
          .update({
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'overall_score': average,
            'strongest_area': strongest,
            'weakest_area': weakest,
            'points_earned': 3 + scored.length,
          })
          .eq('id', session.id);

      final updated = await byId(session.id);
      return updated ?? session;
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final interviewRepositoryProvider = Provider<InterviewRepository>(
  (ref) => InterviewRepository(ref.watch(supabaseProvider)),
);

final interviewHistoryProvider = FutureProvider<List<InterviewSession>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(interviewRepositoryProvider).history();
});

/// The seeded employer packs. Reference data, so it is fetched once and kept.
final companyPacksProvider = FutureProvider<List<CompanyPack>>(
  (ref) => ref.watch(interviewRepositoryProvider).companyPacks(),
);
