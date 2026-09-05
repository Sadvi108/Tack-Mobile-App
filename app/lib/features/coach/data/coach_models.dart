/// One line of the conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.body,
    required this.createdAt,
    this.answeredBy,
  });

  final String id;
  final String role;
  final String body;
  final DateTime createdAt;

  /// `data` when Tack answered from its own numbers and spent nothing,
  /// `model` when it cost one of the day's three. Null on a student's line.
  final String? answeredBy;

  bool get isStudent => role == 'student';
  bool get wasFree => answeredBy == 'data';

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
    id: '${row['id']}',
    role: (row['role'] as String?) ?? 'coach',
    body: (row['body'] as String?) ?? '',
    createdAt:
        DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
    answeredBy: row['answered_by'] as String?,
  );
}

/// What the coach sent back.
class CoachReply {
  const CoachReply({
    required this.threadId,
    required this.remaining,
    this.body,
    this.answeredBy,
    this.limitMessage,
  });

  final String threadId;
  final int remaining;
  final String? body;
  final String? answeredBy;

  /// Set instead of [body] when the day's three are gone. Phrased as a trade
  /// that keeps Tack free, never as a telling-off.
  final String? limitMessage;

  bool get hitLimit => limitMessage != null;
  bool get wasFree => answeredBy == 'data';

  factory CoachReply.fromJson(Map<String, dynamic> json) => CoachReply(
    threadId: '${json['threadId']}',
    remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    body: json['reply'] as String?,
    answeredBy: json['answeredBy'] as String?,
    limitMessage: json['limit'] as String?,
  );
}

/// The questions Tack can always answer for nothing.
///
/// Shown on the empty screen because a student who does not know which
/// questions are free will spend the allowance before they learn. Every one of
/// these is answered from their own numbers, so none of them costs anything.
const freeQuestions = <String>[
  'What should I do next?',
  'How am I doing?',
  'What skills am I missing?',
  'How far through my roadmap am I?',
];
