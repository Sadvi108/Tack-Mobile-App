/// How much a path needs a given skill.
enum SkillImportance {
  core,
  important,
  nice;

  static SkillImportance fromWire(String? value) =>
      SkillImportance.values.firstWhere(
        (i) => i.name == value,
        orElse: () => SkillImportance.important,
      );

  String get label => switch (this) {
    SkillImportance.core => 'Must have',
    SkillImportance.important => 'Strongly helps',
    SkillImportance.nice => 'Nice to have',
  };
}

class PathSkill {
  const PathSkill({
    required this.skillId,
    required this.name,
    required this.importance,
  });

  final String skillId;
  final String name;
  final SkillImportance importance;

  factory PathSkill.fromRow(Map<String, dynamic> row) {
    final skill = (row['skills'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PathSkill(
      skillId: (skill['id'] as String?) ?? row['skill_id'] as String,
      name: (skill['name'] as String?) ?? 'Unknown skill',
      importance: SkillImportance.fromWire(row['importance'] as String?),
    );
  }
}

/// One of the ten hand-written career paths.
///
/// Everything here is seeded content written for the Bangladeshi entry-level
/// market. No model produced any of it, and none of it depends on a quota.
class CareerPath {
  const CareerPath({
    required this.id,
    required this.slug,
    required this.title,
    required this.summary,
    required this.category,
    this.salaryMin,
    this.salaryMax,
    this.monthsToJobReady,
    this.demandLevel,
    this.dayToDay = const [],
    this.goodFitIf = const [],
    this.skills = const [],
    this.milestoneCount = 0,
  });

  final String id;
  final String slug;
  final String title;
  final String summary;
  final String category;
  final int? salaryMin;
  final int? salaryMax;
  final int? monthsToJobReady;
  final String? demandLevel;
  final List<String> dayToDay;
  final List<String> goodFitIf;
  final List<PathSkill> skills;
  final int milestoneCount;

  List<PathSkill> get coreSkills =>
      skills.where((s) => s.importance == SkillImportance.core).toList();

  /// "25,000–45,000 BDT a month", or a plain line when the range is unknown.
  String get salaryLabel {
    if (salaryMin == null || salaryMax == null) return 'Varies by employer';
    return '${_thousands(salaryMin!)}–${_thousands(salaryMax!)} BDT a month';
  }

  String get timeLabel =>
      monthsToJobReady == null ? 'Varies' : 'About $monthsToJobReady months';

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  factory CareerPath.fromRow(Map<String, dynamic> row) => CareerPath(
    id: row['id'] as String,
    slug: row['slug'] as String,
    title: row['title'] as String,
    summary: row['summary'] as String,
    category: (row['category'] as String?) ?? 'general',
    salaryMin: (row['salary_min_bdt'] as num?)?.toInt(),
    salaryMax: (row['salary_max_bdt'] as num?)?.toInt(),
    monthsToJobReady: (row['months_to_job_ready'] as num?)?.toInt(),
    demandLevel: row['demand_level'] as String?,
    dayToDay: (row['day_to_day'] as List?)?.cast<String>() ?? const [],
    goodFitIf: (row['good_fit_if'] as List?)?.cast<String>() ?? const [],
    skills: ((row['career_path_skills'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PathSkill.fromRow)
        .toList(),
    milestoneCount:
        ((row['career_path_milestones'] as List?) ?? const []).length,
  );
}

/// How well a student matches a path right now, computed by set comparison.
/// Deterministic — no model is involved in matching, ever.
class PathMatch {
  const PathMatch({
    required this.path,
    required this.have,
    required this.missing,
  });

  final CareerPath path;
  final List<PathSkill> have;
  final List<PathSkill> missing;

  int get total => have.length + missing.length;

  /// Weighted so a missing must-have counts against you more than a missing
  /// nice-to-have.
  int get percent {
    if (total == 0) return 0;
    double weight(SkillImportance i) => switch (i) {
      SkillImportance.core => 3,
      SkillImportance.important => 2,
      SkillImportance.nice => 1,
    };
    final earned = have.fold(0.0, (sum, s) => sum + weight(s.importance));
    final possible = [
      ...have,
      ...missing,
    ].fold(0.0, (sum, s) => sum + weight(s.importance));
    return possible == 0 ? 0 : (earned * 100 / possible).round();
  }

  List<PathSkill> get missingCore =>
      missing.where((s) => s.importance == SkillImportance.core).toList();
}

/// Compares a path's required skills against what the student already has.
PathMatch matchPath(CareerPath path, Set<String> userSkillIds) {
  final have = <PathSkill>[];
  final missing = <PathSkill>[];
  for (final skill in path.skills) {
    (userSkillIds.contains(skill.skillId) ? have : missing).add(skill);
  }
  return PathMatch(path: path, have: have, missing: missing);
}
