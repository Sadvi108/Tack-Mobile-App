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
  });

  final String id;
  final int orderIndex;
  final String question;
  final String? category;
  final String? answerText;
  final bool skipped;
  final AnswerFeedback? feedback;

  bool get isAnswered => (answerText?.isNotEmpty ?? false) || skipped;

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
    );
  }
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
  });

  final String questionId;
  final String role;
  final String question;
  final String? answerText;
  final List<String> toImprove;
  final String? modelAnswer;

  bool get hasNotes =>
      (answerText?.isNotEmpty ?? false) ||
      toImprove.isNotEmpty ||
      (modelAnswer?.isNotEmpty ?? false);

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
    );
  }
}
