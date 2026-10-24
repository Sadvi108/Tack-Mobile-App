/// What an application still needs, as `application_checklist` (0082) ranks
/// it. The rules and their order live in Postgres; this only reads them.
enum ChecklistAction {
  openJob('open_job'),
  practise('practise'),
  prep('prep'),
  attachCv('attach_cv'),
  analyse('analyse'),
  followUp('follow_up');

  const ChecklistAction(this.wire);
  final String wire;

  static ChecklistAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.action,
    required this.isRequired,
  });

  final String id;
  final String title;
  final ChecklistAction action;
  final bool isRequired;

  /// Null for anything this app cannot act on, so a rule added on the server
  /// before the app knows it is skipped rather than shown as a dead button.
  static ChecklistItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final action = ChecklistAction.fromWire(raw['action']);
    if (id is! String || title is! String || action == null) return null;
    return ChecklistItem(
      id: id,
      title: title,
      action: action,
      isRequired: raw['severity'] == 'required',
    );
  }
}

class Checklist {
  const Checklist(this.items);

  /// In precedence order. The first is the next step.
  final List<ChecklistItem> items;

  ChecklistItem? get nextStep => items.firstOrNull;
  List<ChecklistItem> get rest => items.skip(1).toList();
  bool get isEmpty => items.isEmpty;

  factory Checklist.fromJson(Object? raw) {
    final items = raw is Map ? raw['items'] : null;
    if (items is! List) return const Checklist([]);
    return Checklist([for (final item in items) ?ChecklistItem.fromJson(item)]);
  }
}

class TalkingPoint {
  const TalkingPoint(this.point, this.evidence);
  final String point;

  /// The skill or project that backs it. The worker drops any point whose
  /// evidence names neither (`_shared/prep/evidence.ts`).
  final String evidence;
}

class LikelyQuestion {
  const LikelyQuestion(this.question, this.why);
  final String question;
  final String why;
}

class PrepGap {
  const PrepGap(this.skill, this.howToPrepare);
  final String skill;
  final String howToPrepare;
}

class PrepBrief {
  const PrepBrief({
    required this.talkingPoints,
    required this.likelyQuestions,
    required this.questionsToAsk,
    required this.gaps,
  });

  final List<TalkingPoint> talkingPoints;
  final List<LikelyQuestion> likelyQuestions;
  final List<String> questionsToAsk;
  final List<PrepGap> gaps;

  /// Null when there is nothing worth showing: a brief is its talking points.
  static PrepBrief? fromJson(Object? raw) {
    if (raw is! Map) return null;

    List<T> each<T>(Object? list, T? Function(Map<Object?, Object?>) read) => [
      if (list is List)
        for (final entry in list)
          if (entry is Map) ?read(entry),
    ];

    final points = each(raw['talking_points'], (e) {
      final point = e['point'], evidence = e['evidence'];
      return point is String && evidence is String
          ? TalkingPoint(point, evidence)
          : null;
    });
    if (points.isEmpty) return null;

    final asks = raw['questions_to_ask'];
    return PrepBrief(
      talkingPoints: points,
      likelyQuestions: each(raw['likely_questions'], (e) {
        final question = e['question'], why = e['why'];
        return question is String && why is String
            ? LikelyQuestion(question, why)
            : null;
      }),
      questionsToAsk: [
        if (asks is List)
          for (final ask in asks)
            if (ask is String) ask,
      ],
      gaps: each(raw['gaps'], (e) {
        final skill = e['skill'], how = e['how_to_prepare'];
        return skill is String && how is String ? PrepGap(skill, how) : null;
      }),
    );
  }
}

/// A CV in the vault the student can attach to an application.
class CvOption {
  const CvOption(this.id, this.title);
  final String id;
  final String title;
}
