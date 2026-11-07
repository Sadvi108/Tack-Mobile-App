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

/// A chip under a coach reply: a screen to open, labelled by Tack.
///
/// The label always comes from the server (the model only ever picks a route
/// id). The route ids are one list in TypeScript (`_shared/coach/actions.ts`),
/// in SQL (0097's CHECK) and here; tests hold them together.
class CoachAction {
  const CoachAction({required this.route, required this.label, this.slug});

  final String route;
  final String label;

  /// Only on `path`: which career path to open.
  final String? slug;

  static const routes = {
    'interview',
    'practice',
    'analyser',
    'cv_check',
    'cv_builder',
    'roadmap',
    'radar',
    'score',
    'paths',
    'path',
    'applications',
    'profile',
  };

  static final slugPattern = RegExp(r'^[a-z0-9-]{1,80}$');

  /// Null for anything malformed, an unknown route or a bad slug, so a newer
  /// server can add a route without breaking an older app.
  static CoachAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final route = raw['route'];
    final label = raw['label'];
    final slug = raw['slug'];
    if (route is! String || !routes.contains(route)) return null;
    if (label is! String) return null;
    final text = label.trim();
    if (text.length < 2 || text.length > 48) return null;
    if (slug != null && (slug is! String || !slugPattern.hasMatch(slug))) {
      return null;
    }
    return CoachAction(route: route, label: text, slug: slug as String?);
  }

  /// At most three, as the database allows.
  static List<CoachAction> listFrom(Object? raw) => [
    if (raw is List)
      for (final a in raw) ?CoachAction.fromJson(a),
  ].take(3).toList();
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
    this.actions = const [],
    this.intent,
  });

  final String id;
  final String role;
  final String body;
  final DateTime createdAt;

  /// `data` when Tack answered from its own numbers and spent nothing,
  /// `model` when it used one AI action. Null on a student's line.
  final String? answeredBy;

  /// Set when the reply was answered from Tack's career guides.
  final List<GuideCitation> citations;

  /// The guides were asked. With no citations, they had nothing to say, and
  /// the reply cost nothing whichever way it was answered.
  final bool fromGuides;

  /// Screens the reply points at. Empty on a student's line and on replies
  /// saved before 0097.
  final List<CoachAction> actions;

  /// What answered it: a router id, or model, cited, guide_refusal or
  /// fallback. Null on a student's line and on older replies.
  final String? intent;

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
    actions: CoachAction.listFrom(row['actions']),
    intent: row['intent'] is String ? row['intent'] as String : null,
  );
}

/// What the coach sent back.
class CoachReply {
  const CoachReply({
    required this.threadId,
    required this.remaining,
    this.body,
    this.answeredBy,
    this.citations = const [],
    this.fromGuides = false,
    this.actions = const [],
    this.intent,
  });

  final String threadId;
  final int remaining;
  final String? body;
  final String? answeredBy;
  final List<GuideCitation> citations;
  final bool fromGuides;
  final List<CoachAction> actions;
  final String? intent;

  bool get guideRefusal => fromGuides && citations.isEmpty;
  bool get wasFree => answeredBy == 'data';

  factory CoachReply.fromJson(Map<String, dynamic> json) => CoachReply(
    threadId: '${json['threadId']}',
    remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    body: json['reply'] as String?,
    answeredBy: json['answeredBy'] as String?,
    citations: GuideCitation.listFrom(json['citations']),
    fromGuides: json['citations'] is List,
    actions: CoachAction.listFrom(json['actions']),
    intent: json['intent'] is String ? json['intent'] as String : null,
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
