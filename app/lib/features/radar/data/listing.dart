/// One opening, as `public.radar_feed` returns it.
///
/// Parsed defensively: this is a boundary, the shape will grow as boards are
/// added, and a feed that throws because one salary field arrived null is
/// worse than a feed missing that salary.
class Listing {
  const Listing({
    required this.id,
    required this.source,
    required this.title,
    required this.url,
    required this.applyUrl,
    this.company,
    this.location,
    this.isRemote = false,
    this.salary,
    this.level,
    this.postedAt,
    this.fit,
    this.asks = 0,
    this.have = 0,
    this.matchedSkills = const [],
    this.missingSkills = const [],
    this.savedApplicationId,
  });

  final String id;

  /// Which board it came from. Shown, because a student deserves to know who
  /// is telling them about a job.
  final String source;

  final String title;
  final String url;
  final String applyUrl;
  final String? company;
  final String? location;
  final bool isRemote;
  final String? salary;
  final String? level;
  final DateTime? postedAt;

  /// How well it fits, 0–100.
  ///
  /// **Null means "we could not tell"** — Tack read no known skills in the
  /// listing — and that is not the same as zero. A listing with no readable
  /// requirements must never be shown as a 0% match, because the student would
  /// read that as "you are not good enough" when it actually means "this
  /// posting does not say what it wants".
  final int? fit;

  /// How many skills the listing asks for, and how many the student has.
  final int asks;
  final int have;

  final List<String> matchedSkills;
  final List<String> missingSkills;

  /// Set once the student has saved this into their tracker.
  final String? savedApplicationId;

  bool get isSaved => savedApplicationId != null;
  bool get isScored => fit != null;

  String get sourceLabel => switch (source) {
    'careerjet' => 'Careerjet',
    'aijobs' => 'AI jobs',
    _ => source,
  };

  /// "2 days ago", never a bare date.
  String? postedRelativeTo(DateTime now) {
    final at = postedAt;
    if (at == null) return null;
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(at.year, at.month, at.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    if (days < 14) return 'Last week';
    if (days < 60) return '${(days / 7).round()} weeks ago';
    return 'A while ago';
  }

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
    id: '${json['id']}',
    source: (json['source'] as String?) ?? 'aijobs',
    title: (json['title'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    applyUrl:
        (json['apply_url'] as String?) ?? (json['url'] as String?) ?? '',
    company: _text(json['company']),
    location: _text(json['location']),
    isRemote: json['remote'] == true,
    salary: _text(json['salary']),
    level: _text(json['level']),
    postedAt: DateTime.tryParse('${json['posted_at']}')?.toLocal(),
    fit: (json['fit'] as num?)?.toInt(),
    asks: (json['asks'] as num?)?.toInt() ?? 0,
    have: (json['have'] as num?)?.toInt() ?? 0,
    matchedSkills: _strings(json['matched_skills']),
    missingSkills: _strings(json['missing_skills']),
    savedApplicationId: _text(json['saved_application_id']),
  );

  static String? _text(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static List<String> _strings(Object? v) => [
    for (final x in (v as List?) ?? const []) ?_text(x),
  ];
}

/// What Radar answered with, including which boards could not be reached.
class RadarResult {
  const RadarResult({required this.listings, this.problems = const {}});

  final List<Listing> listings;

  /// Keyed by source. A board being unconfigured or down is said out loud
  /// rather than shown as "nothing found", which would be a lie.
  final Map<String, String> problems;

  static const empty = RadarResult(listings: []);

  bool get isMissingCareerjet => problems.containsKey('careerjet');

  factory RadarResult.fromJson(Map<String, dynamic> json) => RadarResult(
    listings: [
      for (final row in (json['listings'] as List?) ?? const [])
        if (row is Map) Listing.fromJson(row.cast<String, dynamic>()),
    ],
    problems: {
      for (final e in
          ((json['problems'] as Map?) ?? const {}).cast<String, dynamic>().entries)
        e.key: '${e.value}',
    },
  );
}
