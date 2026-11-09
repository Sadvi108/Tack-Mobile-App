import '../../../core/jobs/job_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'interview_catalog.dart';
import 'interview_models.dart';

class InterviewRepository {
  const InterviewRepository(this._db, [this._jobs]);

  final JobRepository? _jobs;

  final SupabaseClient _db;

  static const _select = '''
    id, role, role_slug, session_type, difficulty, timer_enabled, completed_at,
    overall_score, strongest_area, weakest_area, points_earned,
    interview_questions(
      id, order_index, question, category, answer_text, skipped,
      key_points, pool_question_id, self_check,
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

  /// Every role a student can practise, by field, and the one suggested from
  /// their own path, target role or field. Empty before any role is seeded.
  Future<InterviewCatalog> catalog() async {
    try {
      return InterviewCatalog.fromJson(await _db.rpc('interview_catalog'));
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Starts a practice session from the role's question pool.
  ///
  /// Free: no Edge Function, no model and no AI action. The database draws
  /// questions this student has not seen lately and writes the session and
  /// its questions in one transaction (`start_practice_session`, 0096).
  Future<InterviewSession> startPractice({
    required String roleSlug,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timerEnabled,
    int count = 5,
  }) async {
    try {
      final result = await _db.rpc(
        'start_practice_session',
        params: {
          'p_role_slug': roleSlug,
          'p_session_type': type.name,
          'p_difficulty': difficulty.name,
          'p_count': count,
          'p_timer': timerEnabled,
        },
      );
      final id = (result as Map?)?['session_id'];
      final created = id is String ? await byId(id) : null;
      if (created == null) {
        throw const Failure('The session could not be opened. Try again.');
      }
      return created;
    } on PostgrestException catch (e) {
      throw _practiceFailure(e);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The sentences for the start's own refusals (0096). Anything else is the
  /// usual mapping.
  static Failure _practiceFailure(PostgrestException e) {
    final message = e.message;
    return switch (e.code) {
      'P0002' => Failure(
        'That role is not in the question bank yet. Choose another role.',
        cause: e,
        code: 'unknown_role',
      ),
      'P0001' when message.contains('too_many_sessions') => Failure(
        'That is a lot of practice for one day. Take a break and come back '
        'tomorrow.',
        cause: e,
        code: 'too_many_sessions',
      ),
      'P0001' => Failure(
        'This role does not have enough questions yet. Choose another role.',
        cause: e,
        code: 'not_enough_questions',
      ),
      '22023' => Failure(
        'Choose between 3 and 10 questions.',
        cause: e,
        code: e.code,
      ),
      _ => Failure.from(e),
    };
  }

  /// Saves the student's own answer and what they ticked against the key
  /// points. Free. The 0078 trigger then brings the answer back in Practise
  /// again.
  Future<void> saveOwnAnswer({
    required String questionId,
    required String answer,
    required List<int> covered,
    required int total,
  }) async {
    final check = SelfCheck.fromJson({'covered': covered, 'total': total});
    if (check == null) {
      throw const Failure('That check could not be saved. Try again.');
    }
    try {
      await _db
          .from('interview_questions')
          .update({
            'answer_text': answer,
            'answered_at': DateTime.now().toUtc().toIso8601String(),
            'self_check': check.toJson(),
          })
          .eq('id', questionId)
          .eq('user_id', _uid);
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
          // ascending explicitly: the Dart client's order() defaults to
          // descending, which listed these Shohoz-first on the device.
          .order('name', ascending: true);
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

  /// Starts a session through the interview function, as builds before the
  /// question pool did. Kept for old paths; [startPractice] is the free start.
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

      var body =
          (response.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (response.status == 202 && _jobs != null) {
        body = await _jobs.resolve(body);
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
      var body =
          (response.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (response.status == 202 && _jobs != null) {
        body = await _jobs.resolve(body);
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
          .eq('id', questionId)
          .eq('user_id', _uid);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Closes the session and records the summary. Points are awarded for
  /// finishing, because finishing is the behaviour worth encouraging.
  ///
  /// The score is the AI average, or null when nothing was scored by AI, so a
  /// free session never counts as a zero in the readiness score. Strongest and
  /// weakest come from AI-scored answers only.
  Future<InterviewSession> complete(InterviewSession session) async {
    try {
      final scored = session.questions.where((q) => q.isAiScored).toList();

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
            'overall_score': session.overallForStorage,
            'strongest_area': strongest,
            'weakest_area': weakest,
            'points_earned': 3 + session.attempted,
          })
          .eq('id', session.id)
          .eq('user_id', _uid);

      final updated = await byId(session.id);
      return updated ?? session;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Answered questions due for practice today, at most ten.
  Future<List<DueQuestion>> dueQuestions() async {
    try {
      final rows = await _db.rpc('interview_due');
      return [
        for (final row in (rows as List?) ?? const [])
          if (row is Map) ?DueQuestion.fromJson(row.cast<String, dynamic>()),
      ];
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Records a self-grade. Returns how many days until it comes back.
  Future<int> review(String questionId, ReviewGrade grade) async {
    try {
      final result = await _db.rpc(
        'review_interview_question',
        params: {'p_question_id': questionId, 'p_grade': grade.name},
      );
      return ((result as Map?)?['interval_days'] as num?)?.toInt() ?? 1;
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final interviewRepositoryProvider = Provider<InterviewRepository>(
  (ref) => InterviewRepository(
    ref.watch(supabaseProvider),
    ref.watch(jobRepositoryProvider),
  ),
);

final interviewHistoryProvider = FutureProvider<List<InterviewSession>>((
  ref,
) async {
  if (ref.watch(currentUserProvider)?.id == null) return const [];
  return ref.watch(interviewRepositoryProvider).history();
});

/// The seeded employer packs. Reference data, so it is fetched once and kept.
final companyPacksProvider = FutureProvider<List<CompanyPack>>(
  (ref) => ref.watch(interviewRepositoryProvider).companyPacks(),
);

/// What is due for practice today. Empty when signed out.
final dueQuestionsProvider = FutureProvider.autoDispose<List<DueQuestion>>((
  ref,
) async {
  if (ref.watch(currentUserProvider)?.id == null) return const [];
  return ref.watch(interviewRepositoryProvider).dueQuestions();
});
