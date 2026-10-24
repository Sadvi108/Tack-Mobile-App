/// A sentence of Tack's own career guides that a reply stood on. The worker
/// has already checked that the quote is word for word from that sentence
/// (`_shared/coach/cited.ts`).
class GuideCitation {
  const GuideCitation({
    required this.chunkId,
    required this.pathSlug,
    required this.pathTitle,
    required this.quote,
  });

  final String chunkId;
  final String pathSlug;
  final String pathTitle;
  final String quote;

  static GuideCitation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chunkId = raw['chunk_id'];
    final slug = raw['path_slug'];
    final title = raw['path_title'];
    final quote = raw['quote'];
    if (chunkId is! String ||
        slug is! String ||
        title is! String ||
        quote is! String) {
      return null;
    }
    return GuideCitation(
      chunkId: chunkId,
      pathSlug: slug,
      pathTitle: title,
      quote: quote,
    );
  }

  static List<GuideCitation> listFrom(Object? raw) => [
    if (raw is List)
      for (final c in raw) ?GuideCitation.fromJson(c),
  ];
}

/// One career guide a reply cited, once, in the order it was first cited.
typedef GuideRef = ({String slug, String title});

List<GuideRef> _guidesOf(List<GuideCitation> citations) {
  final seen = <String>{};
  return [
    for (final c in citations)
      if (seen.add(c.pathSlug)) (slug: c.pathSlug, title: c.pathTitle),
  ];
}

/// One line of the conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.body,
    required this.createdAt,
    this.answeredBy,
    this.citations = const [],
    this.fromGuides = false,
  });

  final String id;
  final String role;
  final String body;
  final DateTime createdAt;

  /// `data` when Tack answered from its own numbers and spent nothing,
  /// `model` when it cost one of the day's three. Null on a student's line.
  final String? answeredBy;

  /// Set when the reply was answered from Tack's career guides.
  final List<GuideCitation> citations;

  /// The guides were asked. With no citations, they had nothing to say, and
  /// the reply cost nothing whichever way it was answered.
  final bool fromGuides;

  bool get isStudent => role == 'student';
  bool get wasFree => answeredBy == 'data';
  bool get isGrounded => citations.isNotEmpty;
  bool get guideRefusal => fromGuides && citations.isEmpty;
  List<GuideRef> get guides => _guidesOf(citations);

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
    id: '${row['id']}',
    role: (row['role'] as String?) ?? 'coach',
    body: (row['body'] as String?) ?? '',
    createdAt:
        DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
    answeredBy: row['answered_by'] as String?,
    citations: GuideCitation.listFrom(row['citations']),
    fromGuides: row['citations'] is List,
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
    this.citations = const [],
    this.fromGuides = false,
  });

  final String threadId;
  final int remaining;
  final String? body;
  final String? answeredBy;
  final List<GuideCitation> citations;
  final bool fromGuides;

  bool get guideRefusal => fromGuides && citations.isEmpty;

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
    citations: GuideCitation.listFrom(json['citations']),
    fromGuides: json['citations'] is List,
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
