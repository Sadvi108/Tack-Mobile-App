/// A career path Tack thinks would suit this student, and why.
///
/// The "why" is not decoration. The ranking is arithmetic over what the
/// student entered — their subject, their stated target, the industries they
/// picked, the skills they have — and a suggestion that cannot say where it
/// came from is one a student has no reason to trust. Every path shown carries
/// at least one reason; a path with none is not shown at all.
class PathSuggestion {
  const PathSuggestion({
    required this.id,
    required this.slug,
    required this.title,
    required this.score,
    required this.reasons,
    this.summary,
    this.salaryMin,
    this.salaryMax,
    this.months,
    this.demand,
    this.isTarget = false,
    this.followed = false,
  });

  final String id;
  final String slug;
  final String title;
  final int score;

  /// Plain sentences, strongest first.
  final List<String> reasons;

  final String? summary;
  final int? salaryMin;
  final int? salaryMax;
  final int? months;
  final String? demand;

  /// This is the role the student said they were aiming at.
  final bool isTarget;

  /// They already follow it, so it is context rather than a suggestion.
  final bool followed;

  /// Entry-level pay in Dhaka, as a range a student can read at a glance.
  ///
  /// Kept short so three facts sit on one line instead of stacking into three
  /// rows: "BDT 28–50k" says the same as "BDT 28k–50k a month" beside a pill
  /// that already reads "10 months".
  String? get salaryRange {
    final min = salaryMin, max = salaryMax;
    if (min == null || max == null) return null;
    String k(int v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';
    return 'BDT ${(min / 1000).round()}–${k(max)}';
  }

  factory PathSuggestion.fromJson(Map<String, dynamic> json) => PathSuggestion(
    id: '${json['id']}',
    slug: (json['slug'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    score: (json['score'] as num?)?.toInt() ?? 0,
    reasons: [
      for (final r in (json['reasons'] as List?) ?? const [])
        if (r is String) r,
    ],
    summary: json['summary'] as String?,
    salaryMin: (json['salary_min'] as num?)?.toInt(),
    salaryMax: (json['salary_max'] as num?)?.toInt(),
    months: (json['months'] as num?)?.toInt(),
    demand: json['demand'] as String?,
    isTarget: json['is_target'] == true,
    followed: json['followed'] == true,
  );
}

/// What Tack worked out about the student, and what it suggests as a result.
class PathAdvice {
  const PathAdvice({required this.suggestions, this.field, this.unsure = true});

  final List<PathSuggestion> suggestions;

  /// The field the student was read as belonging to — from what they picked,
  /// or their stated role, or their degree subject. Null when there was
  /// genuinely nothing to go on, and the screen says so rather than guessing.
  final String? field;

  /// They told us they were not sure of their direction, so the list is wider.
  final bool unsure;

  static const empty = PathAdvice(suggestions: []);

  /// Suggestions they are not already following.
  List<PathSuggestion> get fresh =>
      suggestions.where((s) => !s.followed).toList(growable: false);

  bool get hasAnything => suggestions.isNotEmpty;

  factory PathAdvice.fromJson(Map<String, dynamic> json) => PathAdvice(
    field: json['field'] as String?,
    unsure: json['unsure'] != false,
    suggestions: [
      for (final s in (json['suggestions'] as List?) ?? const [])
        if (s is Map) PathSuggestion.fromJson(s.cast<String, dynamic>()),
    ],
  );
}
