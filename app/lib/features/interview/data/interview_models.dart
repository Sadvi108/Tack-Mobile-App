enum InterviewType {
  behavioural,
  technical,
  mixed;

  static InterviewType fromWire(String? v) => InterviewType.values.firstWhere(
    (t) => t.name == v,
    orElse: () => InterviewType.mixed,
  );

  String get label => switch (this) {
    InterviewType.behavioural => 'About you',
    InterviewType.technical => 'Technical',
    InterviewType.mixed => 'A bit of both',
  };
}

enum Difficulty {
  easy,
  medium,
  hard;

  static Difficulty fromWire(String? v) => Difficulty.values.firstWhere(
    (d) => d.name == v,
    orElse: () => Difficulty.medium,
  );

  String get label => switch (this) {
    Difficulty.easy => 'Gentle',
    Difficulty.medium => 'Realistic',
    Difficulty.hard => 'Tough',
  };
}

class InterviewQuestion {
  const InterviewQuestion({
    required this.id,
    required this.orderIndex,
    required this.question,
    this.category,
    this.answerText,
    this.skipped = false,
    this.feedback,
    this.keyPoints = const [],
    this.poolQuestionId,
    this.selfCheck,
  });

  final String id;
  final int orderIndex;
  final String question;
  final String? category;
  final String? answerText;
  final bool skipped;
  final AnswerFeedback? feedback;

  /// What a strong answer covers, from the question pool. Empty for company
  /// packs and for sets written before the pool existed.
  final List<String> keyPoints;

  /// The pool question this was drawn from, so the next draw can avoid it.
  final String? poolQuestionId;

  /// What the student ticked when they checked their own answer.
  final SelfCheck? selfCheck;

  bool get isAnswered => (answerText?.isNotEmpty ?? false) || skipped;

  /// AI feedback on an answer that was attempted.
  bool get isAiScored => feedback != null && !skipped;

  factory InterviewQuestion.fromRow(Map<String, dynamic> row) {
    final rawFeedback = row['interview_feedback'];
    final feedbackRow = rawFeedback is List
        ? (rawFeedback.isEmpty ? null : rawFeedback.first as Map)
        : rawFeedback as Map?;
    return InterviewQuestion(
      id: row['id'] as String,
      orderIndex: (row['order_index'] as num?)?.toInt() ?? 0,
      question: row['question'] as String,
      category: row['category'] as String?,
      answerText: row['answer_text'] as String?,
      skipped: row['skipped'] as bool? ?? false,
      feedback: feedbackRow == null
          ? null
          : AnswerFeedback.fromRow(feedbackRow.cast<String, dynamic>()),
      keyPoints: parseKeyPoints(row['key_points']),
      poolQuestionId: row['pool_question_id'] is String
          ? row['pool_question_id'] as String
          : null,
      selfCheck: SelfCheck.fromJson(row['self_check']),
    );
  }
}

/// Key points as stored: strings only, trimmed, never blank, at most four.
/// Anything else in the column is ignored rather than drawn.
List<String> parseKeyPoints(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ].take(4).toList(growable: false);
}

/// Which key points a student said their answer covered:
/// `{"covered": [0, 2], "total": 4}`.
class SelfCheck {
  const SelfCheck({required this.covered, required this.total});

  /// Distinct indexes into the key points, in order.
  final List<int> covered;

  /// How many key points there were, 1 to 4.
  final int total;

  /// Null for anything that is not a usable check. Indexes outside the key
  /// points and repeats are dropped.
  static SelfCheck? fromJson(Object? value) {
    if (value is! Map) return null;
    final total = value['total'];
    final covered = value['covered'];
    if (total is! int || total < 1 || total > 4 || covered is! List) {
      return null;
    }
    final indexes = <int>{
      for (final i in covered)
        if (i is int && i >= 0 && i < total) i,
    }.toList()..sort();
    return SelfCheck(covered: indexes, total: total);
  }

  Map<String, Object> toJson() => {'covered': covered, 'total': total};
}

class AnswerFeedback {
  const AnswerFeedback({
    required this.score,
    required this.wentWell,
    required this.toImprove,
    this.modelAnswer,
  });

  final double score;

  /// What went well is always shown first. A student practising for their
  /// first interview is nervous enough without leading with the criticism.
  final List<String> wentWell;
  final List<String> toImprove;
  final String? modelAnswer;

  factory AnswerFeedback.fromRow(Map<String, dynamic> row) => AnswerFeedback(
    score: (row['score'] as num?)?.toDouble() ?? 0,
    wentWell: (row['went_well'] as List?)?.cast<String>() ?? const [],
    toImprove: (row['to_improve'] as List?)?.cast<String>() ?? const [],
    modelAnswer: row['model_answer'] as String?,
  );

  factory AnswerFeedback.fromJson(Map<String, dynamic> json) => AnswerFeedback(
    score: (json['score'] as num?)?.toDouble() ?? 0,
    wentWell: (json['went_well'] as List?)?.cast<String>() ?? const [],
    toImprove: (json['to_improve'] as List?)?.cast<String>() ?? const [],
    modelAnswer: json['model_answer'] as String?,
  );
}

class InterviewSession {
  const InterviewSession({
    required this.id,
    required this.role,
    this.roleSlug,
    required this.type,
    required this.difficulty,
    required this.timerEnabled,
    required this.questions,
    this.completedAt,
    this.overallScore,
    this.strongestArea,
    this.weakestArea,
    this.pointsEarned = 0,
  });

  final String id;
  final String role;

  /// The pool role this session was drawn for. Null for company packs and for
  /// sessions started before the pool existed.
  final String? roleSlug;
  final InterviewType type;
  final Difficulty difficulty;
  final bool timerEnabled;
  final List<InterviewQuestion> questions;
  final DateTime? completedAt;
  final double? overallScore;
  final String? strongestArea;
  final String? weakestArea;
  final int pointsEarned;

  bool get isComplete => completedAt != null;
  int get answeredCount => questions.where((q) => q.isAnswered).length;

  InterviewQuestion? get nextUnanswered {
    for (final q in questions) {
      if (!q.isAnswered) return q;
    }
    return null;
  }

  /// The average of every answer that was actually attempted. A skipped
  /// question is not a zero — it was not an attempt.
  double get averageScore {
    final scored = questions
        .where((q) => q.feedback != null && !q.skipped)
        .map((q) => q.feedback!.score)
        .toList();
    if (scored.isEmpty) return 0;
    return scored.reduce((a, b) => a + b) / scored.length;
  }

  /// Whether any answer got AI feedback.
  bool get anyAiScored => questions.any((q) => q.isAiScored);

  /// Answers the student actually gave and checked, by AI or by themselves.
  int get attempted => questions
      .where((q) => !q.skipped && (q.feedback != null || q.selfCheck != null))
      .length;

  int get keyPointsCovered =>
      questions.fold(0, (sum, q) => sum + (q.selfCheck?.covered.length ?? 0));

  int get keyPointsTotal =>
      questions.fold(0, (sum, q) => sum + (q.selfCheck?.total ?? 0));

  /// What is stored as the session's score. Null when nothing was scored by
  /// AI, so a free practice session never counts as a zero in the readiness
  /// score.
  double? get overallForStorage => anyAiScored ? averageScore : null;

  factory InterviewSession.fromRow(Map<String, dynamic> row) {
    final questions =
        ((row['interview_questions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(InterviewQuestion.fromRow)
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return InterviewSession(
      id: row['id'] as String,
      role: row['role'] as String,
      roleSlug: row['role_slug'] is String ? row['role_slug'] as String : null,
      type: InterviewType.fromWire(row['session_type'] as String?),
      difficulty: Difficulty.fromWire(row['difficulty'] as String?),
      timerEnabled: row['timer_enabled'] as bool? ?? false,
      questions: questions,
      completedAt: DateTime.tryParse('${row['completed_at']}')?.toLocal(),
      overallScore: (row['overall_score'] as num?)?.toDouble(),
      strongestArea: row['strongest_area'] as String?,
      weakestArea: row['weakest_area'] as String?,
      pointsEarned: (row['points_earned'] as num?)?.toInt() ?? 0,
    );
  }
}

/// An employer a student is likely to be interviewing with.
///
/// Seeded, not user-generated: what bKash asks is a fact about bKash, and
/// letting students write these would turn a reference into a rumour.
class CompanyPack {
  const CompanyPack({
    required this.slug,
    required this.name,
    required this.about,
    required this.questions,
  });

  final String slug;
  final String name;
  final String about;
  final List<String> questions;

  factory CompanyPack.fromRow(Map<String, dynamic> row) => CompanyPack(
    slug: row['slug'] as String,
    name: row['name'] as String,
    about: (row['about'] as String?) ?? '',
    questions: ((row['questions'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((q) => (q['question'] as String?) ?? '')
        .where((q) => q.isNotEmpty)
        .toList(growable: false),
  );
}

/// How a student rates their own answer when a question comes back.
enum ReviewGrade {
  again,
  hard,
  good,
  easy;

  String get label => switch (this) {
    ReviewGrade.again => 'Again',
    ReviewGrade.hard => 'Hard',
    ReviewGrade.good => 'Good',
    ReviewGrade.easy => 'Easy',
  };
}

/// An answered question that is due for practice, from `interview_due()`.
class DueQuestion {
  const DueQuestion({
    required this.questionId,
    required this.role,
    required this.question,
    this.answerText,
    this.toImprove = const [],
    this.modelAnswer,
    this.keyPoints = const [],
    this.category,
  });

  final String questionId;
  final String role;
  final String question;
  final String? answerText;
  final List<String> toImprove;
  final String? modelAnswer;

  /// What a strong answer covers, when the question came from the pool.
  final List<String> keyPoints;
  final String? category;

  bool get hasNotes =>
      (answerText?.isNotEmpty ?? false) ||
      toImprove.isNotEmpty ||
      (modelAnswer?.isNotEmpty ?? false) ||
      keyPoints.isNotEmpty;

  /// Null when the row is missing what the screen cannot do without.
  static DueQuestion? fromJson(Map<String, dynamic> json) {
    final id = json['question_id'];
    final question = json['question'];
    if (id is! String || question is! String || question.trim().isEmpty) {
      return null;
    }
    return DueQuestion(
      questionId: id,
      role: (json['role'] as String?) ?? '',
      question: question,
      answerText: json['answer_text'] as String?,
      toImprove: [
        for (final item in (json['to_improve'] as List?) ?? const [])
          if (item is String && item.trim().isNotEmpty) item,
      ],
      modelAnswer: json['model_answer'] as String?,
      keyPoints: parseKeyPoints(json['key_points']),
      category: json['category'] is String ? json['category'] as String : null,
    );
  }
}
