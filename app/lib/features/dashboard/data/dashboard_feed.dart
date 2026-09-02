import '../../../design/tack.dart';
import '../../applications/data/application_models.dart';
import '../../profile/data/education_stage.dart';
import '../../profile/data/profile.dart';
import '../../score/data/readiness.dart';

/// Everything the home screen draws, as returned by `public.dashboard_feed()`.
///
/// Parsing is defensive throughout. This is a boundary: the shape is a jsonb
/// document built by a function that will grow sections over time, and a
/// dashboard that throws because one figure arrived null is worse than a
/// dashboard missing that figure.
class DashboardFeed {
  const DashboardFeed({
    required this.today,
    required this.profile,
    required this.score,
    required this.weekChange,
    required this.streak,
    required this.thisWeek,
    required this.lastWeek,
    required this.trend,
    required this.roadmap,
    required this.counts,
    required this.timeline,
    required this.skillGap,
    required this.skillsHeld,
    required this.skillsAsked,
    required this.cohortAverage,
    required this.cohortSize,
    required this.chosenPaths,
    required this.availablePaths,
    required this.primaryPathTitle,
    required this.primaryPathSlug,
    required this.following,
    required this.documentCount,
    required this.hasCv,
    required this.unreadNotifications,
  });

  final DateTime today;
  final Profile profile;
  final ReadinessScore score;
  final int weekChange;
  final Streak streak;
  final WeekSummary thisWeek;
  final WeekSummary lastWeek;
  final List<TrendPoint> trend;
  final RoadmapSummary roadmap;
  final ApplicationCounts counts;
  final List<TimelineEntry> timeline;
  final List<SkillGap> skillGap;

  /// How many of the chosen path's skills the student already claims, out of
  /// how many it asks for.
  final int skillsHeld;
  final int skillsAsked;

  final int? cohortAverage;
  final int? cohortSize;
  final int chosenPaths;

  /// How many career paths there are to look at. Read from the database rather
  /// than written into the copy, which is how "Ten real jobs" survives someone
  /// adding an eleventh.
  final int availablePaths;

  /// The path the student marked as their target. Null until they pick one —
  /// following a path while browsing is not the same as aiming at it.
  final String? primaryPathTitle;
  final String? primaryPathSlug;

  /// Paths they follow but have not committed to.
  final List<FollowedPath> following;
  final int documentCount;
  final bool hasCv;
  final int unreadNotifications;

  YearMode get mode => profile.mode;

  /// How many of the areas that count in this mode have any score at all.
  ///
  /// A component weighted zero for this student is not an area they are
  /// failing at — it is a question nobody asked them — so it is left out of
  /// both halves of the fraction.
  int get areasCounted => score.components.where((c) => c.max > 0).length;
  int get areasScored =>
      score.components.where((c) => c.max > 0 && c.earned > 0).length;

  /// True when the student has actually chosen what they are aiming at.
  bool get hasTarget => primaryPathTitle != null;

  /// The share of the chosen path's skills the student already has.
  double get skillFit => skillsAsked == 0 ? 0 : skillsHeld / skillsAsked;

  /// Anything already past its date and still not done.
  List<TimelineEntry> get overdue =>
      timeline.where((e) => e.isOverdue).toList(growable: false);

  /// The next fortnight, overdue items excluded — those get their own card,
  /// because burying a missed deadline in a list of upcoming ones is how it
  /// gets missed twice.
  List<TimelineEntry> get upcoming =>
      timeline.where((e) => !e.isOverdue).toList(growable: false);

  factory DashboardFeed.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) =>
        (json[key] as Map?)?.cast<String, dynamic>() ?? const {};
    List<dynamic> arr(String key) => (json[key] as List?) ?? const [];

    final cohort = (json['cohort'] as Map?)?.cast<String, dynamic>();
    final paths = obj('paths');
    final documents = obj('documents');
    final scoreJson = obj('score');

    return DashboardFeed(
      today: _date(json['today']) ?? DateTime.now(),
      profile: _profile(obj('profile')),
      score: _score(scoreJson),
      weekChange: _int(scoreJson['week_change']),
      streak: Streak.fromJson(obj('streak')),
      thisWeek: WeekSummary.fromJson(obj('this_week')),
      lastWeek: WeekSummary.fromJson(obj('last_week')),
      trend: [
        for (final point in arr('trend'))
          if (point is Map) TrendPoint.fromJson(point.cast<String, dynamic>()),
      ],
      roadmap: RoadmapSummary.fromJson(obj('roadmap')),
      counts: _counts(obj('applications')),
      timeline: [
        for (final entry in arr('timeline'))
          if (entry is Map)
            TimelineEntry.fromJson(entry.cast<String, dynamic>()),
      ],
      skillGap: [
        for (final skill in arr('skill_gap'))
          if (skill is Map) SkillGap.fromJson(skill.cast<String, dynamic>()),
      ],
      skillsHeld: _int(obj('skill_fit')['have']),
      skillsAsked: _int(obj('skill_fit')['total']),
      cohortAverage: cohort == null ? null : _int(cohort['average']),
      cohortSize: cohort == null ? null : _int(cohort['size']),
      chosenPaths: _int(paths['chosen']),
      availablePaths: _int(paths['available']),
      primaryPathTitle: paths['primary_title'] as String?,
      primaryPathSlug: paths['primary_slug'] as String?,
      following: [
        for (final p in (paths['following'] as List?) ?? const [])
          if (p is Map) FollowedPath.fromJson(p.cast<String, dynamic>()),
      ],
      documentCount: _int(documents['count']),
      hasCv: documents['has_cv'] == true,
      unreadNotifications: _int(json['unread_notifications']),
    );
  }

  static Profile _profile(Map<String, dynamic> json) => Profile(
    id: '${json['id']}',
    fullName: json['full_name'] as String?,
    stage: EducationStage.fromWire(json['stage'] as String?),
    yearOfStudy: _intOrNull(json['year_of_study']),
    yearsTotal: _intOrNull(json['years_total']),
    expectedGraduation: _date(json['expected_graduation']),
    mode: YearMode.fromWire(json['mode'] as String?),
    targetRole: json['target_role'] as String?,
    onboardingCompletedAt: _date(json['onboarding_completed_at']),
  );

  static ReadinessScore _score(Map<String, dynamic> json) {
    final raw = (json['components'] as Map?)?.cast<String, dynamic>() ?? {};
    return ReadinessScore(
      total: _int(json['total']),
      mode: YearMode.fromWire(json['mode'] as String?),
      delta: _int(json['delta']),
      computedAt: _date(json['computed_at']) ?? DateTime.now(),
      components: [
        for (final entry in raw.entries)
          if (entry.value is Map)
            ScoreComponent.fromJson(
              entry.key,
              (entry.value as Map).cast<String, dynamic>(),
            ),
      ],
    );
  }

  static ApplicationCounts _counts(Map<String, dynamic> json) {
    final byName = {for (final s in TackStatus.values) s.name: s};
    final tally = <TackStatus, int>{};
    for (final entry in json.entries) {
      final status = byName[entry.key];
      if (status != null) tally[status] = _int(entry.value);
    }
    return ApplicationCounts(tally);
  }
}

/// Consecutive days the student did something. Not a game mechanic — it is the
/// only figure on the screen that rewards showing up rather than achieving
/// something, which is what carries a first-year through a quiet month.
class Streak {
  const Streak({
    required this.current,
    required this.longest,
    required this.days,
  });

  final int current;
  final int longest;

  /// Active days inside the last 28, oldest first.
  final List<DateTime> days;

  static const empty = Streak(current: 0, longest: 0, days: []);

  bool get isPersonalBest => current > 0 && current >= longest;

  bool wasActiveOn(DateTime day) => days.any(
    (d) => d.year == day.year && d.month == day.month && d.day == day.day,
  );

  factory Streak.fromJson(Map<String, dynamic> json) => Streak(
    current: _int(json['current']),
    longest: _int(json['longest']),
    days: [for (final day in (json['days'] as List?) ?? const []) ?_date(day)],
  );
}

/// One week of the student's own activity, for the momentum comparison.
class WeekSummary {
  const WeekSummary({
    required this.moves,
    required this.activeDays,
    required this.tasksDone,
    required this.taskPoints,
    required this.applicationsAdded,
    required this.interviewsPractised,
    required this.documentsAdded,
    required this.skillsAdded,
    required this.projectsAdded,
    required this.scoreGained,
  });

  /// Everything the student did, counted by the database.
  ///
  /// Not summed from the named fields below. It used to be, and it disagreed
  /// with the streak: adding seven skills lit up a day on the streak strip
  /// while this total stayed at zero, so one card said "you showed up" and the
  /// one under it said "you did nothing". Both now come from
  /// `public.tack_activity`, which is the only place activity is defined.
  final int moves;

  /// Distinct days inside the week with any activity on them.
  final int activeDays;

  final int tasksDone;
  final int taskPoints;
  final int applicationsAdded;
  final int interviewsPractised;
  final int documentsAdded;
  final int skillsAdded;
  final int projectsAdded;
  final int scoreGained;

  static const empty = WeekSummary(
    moves: 0,
    activeDays: 0,
    tasksDone: 0,
    taskPoints: 0,
    applicationsAdded: 0,
    interviewsPractised: 0,
    documentsAdded: 0,
    skillsAdded: 0,
    projectsAdded: 0,
    scoreGained: 0,
  );

  bool get isQuiet => moves == 0;

  factory WeekSummary.fromJson(Map<String, dynamic> json) => WeekSummary(
    moves: _int(json['moves']),
    activeDays: _int(json['active_days']),
    tasksDone: _int(json['tasks_done']),
    taskPoints: _int(json['task_points']),
    applicationsAdded: _int(json['applications_added']),
    interviewsPractised: _int(json['interviews_practised']),
    documentsAdded: _int(json['documents_added']),
    skillsAdded: _int(json['skills_added']),
    projectsAdded: _int(json['projects_added']),
    scoreGained: _int(json['score_gained']),
  );
}

class TrendPoint {
  const TrendPoint({required this.week, required this.total});

  final DateTime week;
  final int total;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    week: _date(json['week']) ?? DateTime.now(),
    total: _int(json['total']),
  );
}

class RoadmapSummary {
  const RoadmapSummary({
    required this.done,
    required this.total,
    required this.overdue,
    this.activeMilestone,
    this.nextTaskId,
    this.nextTaskTitle,
    this.nextTaskPoints = 0,
    this.nextTaskMinutes,
  });

  final int done;
  final int total;
  final int overdue;
  final String? activeMilestone;
  final String? nextTaskId;
  final String? nextTaskTitle;
  final int nextTaskPoints;
  final int? nextTaskMinutes;

  static const empty = RoadmapSummary(done: 0, total: 0, overdue: 0);

  bool get exists => total > 0;
  double get fraction => total == 0 ? 0 : done / total;
  int get percent => total == 0 ? 0 : (done * 100 / total).round();

  factory RoadmapSummary.fromJson(Map<String, dynamic> json) {
    final next = (json['next_task'] as Map?)?.cast<String, dynamic>();
    return RoadmapSummary(
      done: _int(json['done']),
      total: _int(json['total']),
      overdue: _int(json['overdue']),
      activeMilestone: json['active_milestone'] as String?,
      nextTaskId: next?['id'] as String?,
      nextTaskTitle: next?['title'] as String?,
      nextTaskPoints: _int(next?['points']),
      nextTaskMinutes: _intOrNull(next?['est_minutes']),
    );
  }
}

/// What kind of thing has a date on it.
enum TimelineKind {
  task,
  application,
  closing;

  static TimelineKind fromWire(String? value) => TimelineKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => TimelineKind.task,
  );

  String get label => switch (this) {
    TimelineKind.task => 'Roadmap',
    TimelineKind.application => 'Follow up',
    TimelineKind.closing => 'Closes',
  };
}

class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.on,
    required this.route,
    required this.isOverdue,
    this.subtitle,
    this.points = 0,
  });

  final TimelineKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final DateTime on;
  final String route;
  final bool isOverdue;
  final int points;

  /// Whole days from today. Negative when the date has passed.
  int daysFrom(DateTime today) {
    final a = DateTime(today.year, today.month, today.day);
    final b = DateTime(on.year, on.month, on.day);
    return b.difference(a).inDays;
  }

  /// "Today", "Tomorrow", "In 3 days". Deliberately never a bare date: a
  /// student reading "12 Sep" has to do the subtraction themselves.
  String relativeTo(DateTime today) {
    final days = daysFrom(today);
    if (days < -1) return '${-days} days late';
    if (days == -1) return 'Yesterday';
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 7) return 'In $days days';
    if (days < 14) return 'Next week';
    return 'In ${(days / 7).round()} weeks';
  }

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
    kind: TimelineKind.fromWire(json['kind'] as String?),
    id: '${json['id']}',
    title: (json['title'] as String?) ?? '',
    subtitle: (json['subtitle'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['subtitle'] as String).trim(),
    on: _date(json['on']) ?? DateTime.now(),
    route: (json['route'] as String?) ?? '/home',
    isOverdue: json['overdue'] == true,
    points: _int(json['points']),
  );
}

/// A path the student follows but has not made their target.
class FollowedPath {
  const FollowedPath({
    required this.id,
    required this.title,
    required this.slug,
  });

  final String id;
  final String title;
  final String slug;

  factory FollowedPath.fromJson(Map<String, dynamic> json) => FollowedPath(
    id: '${json['id']}',
    title: (json['title'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
  );
}

class SkillGap {
  const SkillGap({
    required this.id,
    required this.name,
    required this.importance,
  });

  final String id;
  final String name;

  /// `core`, `important` or `nice`, straight from `skill_importance`.
  final String importance;

  bool get isCore => importance == 'core';

  factory SkillGap.fromJson(Map<String, dynamic> json) => SkillGap(
    id: '${json['id']}',
    name: (json['name'] as String?) ?? '',
    importance: (json['importance'] as String?) ?? 'important',
  );
}

int _int(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

int? _intOrNull(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse('$value')?.toLocal();
}
