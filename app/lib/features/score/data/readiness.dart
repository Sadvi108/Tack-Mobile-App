import '../../profile/data/profile.dart';

/// One of the eleven things the readiness score is made of.
///
/// The numbers come from the server. The label and the action sentence live
/// here because they are copy, and copy belongs where it can be reviewed.
class ScoreComponent {
  const ScoreComponent({
    required this.key,
    required this.earned,
    required this.max,
    required this.ratio,
  });

  final String key;
  final int earned;
  final int max;
  final double ratio;

  int get available => max - earned;

  /// Nothing scored, partly scored, or doing well. Drives the bar colour.
  bool get isEmpty => earned == 0;
  bool get isHealthy => ratio >= 0.7;

  String get label => switch (key) {
    'profile_completeness' => 'Profile completeness',
    'academic' => 'Academic performance',
    'skills' => 'Skills',
    'projects' => 'Projects',
    'activities' => 'Extracurricular activities',
    'experience' => 'Work experience',
    'cv_quality' => 'CV quality',
    'certifications' => 'Certifications',
    'interview_practice' => 'Interview practice',
    'application_activity' => 'Application activity',
    'roadmap_progress' => 'Roadmap progress',
    _ => key,
  };

  /// One concrete thing to do next. Never a scolding, never a percentage.
  String get action => switch (key) {
    'profile_completeness' => 'Fill in the rest of your profile',
    'academic' => 'Add your CGPA and this semester\'s courses',
    'skills' => 'Add a few more skills you have used',
    'projects' => 'Add a project you have built',
    'activities' => 'Add a club, competition or volunteering role',
    'experience' => 'Add an internship or part-time job',
    'cv_quality' => 'Upload your CV so it can be checked',
    'certifications' => 'Add a certificate you have earned',
    'interview_practice' => 'Practise one interview',
    'application_activity' => 'Apply to a job you have saved',
    'roadmap_progress' => 'Finish a task on your roadmap',
    _ => 'Open this section',
  };

  /// Where the action takes the student.
  String get route => switch (key) {
    'profile_completeness' ||
    'academic' ||
    'skills' ||
    'projects' ||
    'activities' ||
    'experience' ||
    'certifications' => '/profile',
    'cv_quality' => '/vault',
    'interview_practice' => '/interview',
    'application_activity' => '/applications',
    'roadmap_progress' => '/roadmap',
    _ => '/profile',
  };

  /// Rough minutes of effort, used to rank the next three actions by value for
  /// time rather than by raw points. A student with twenty spare minutes
  /// should be pointed at something that fits in twenty minutes.
  int get effortMinutes => switch (key) {
    'profile_completeness' => 5,
    'skills' => 5,
    'academic' => 10,
    'activities' => 10,
    'certifications' => 10,
    'application_activity' => 20,
    'cv_quality' => 20,
    'interview_practice' => 25,
    'experience' => 15,
    'roadmap_progress' => 45,
    'projects' => 240,
    _ => 30,
  };

  factory ScoreComponent.fromJson(String key, Map<String, dynamic> json) =>
      ScoreComponent(
        key: key,
        earned: (json['earned'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt() ?? 0,
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0,
      );
}

/// One snapshot of the score, as stored by public.recompute_readiness.
class ReadinessScore {
  const ReadinessScore({
    required this.total,
    required this.mode,
    required this.components,
    required this.delta,
    required this.computedAt,
  });

  final int total;
  final YearMode mode;
  final List<ScoreComponent> components;
  final int delta;
  final DateTime computedAt;

  /// A student who has just finished onboarding has no snapshot yet. Showing
  /// a zero is honest and matches the design's "everyone starts low" framing.
  static final empty = ReadinessScore(
    total: 0,
    mode: YearMode.explore,
    components: const [],
    delta: 0,
    computedAt: _epochValue,
  );

  static final _epochValue = DateTime.fromMillisecondsSinceEpoch(0);

  /// Components that can still earn points, biggest win first.
  ///
  /// A component worth zero in this year mode is not an opportunity — in
  /// explore mode applications are weighted zero on purpose, and offering a
  /// first-year "apply to a job" would contradict the whole product.
  List<ScoreComponent> get opportunities {
    final list = components.where((c) => c.max > 0 && c.available > 0).toList()
      ..sort((a, b) => b.available.compareTo(a.available));
    return list;
  }

  /// Sorted for the breakdown screen: most points still available first, so
  /// the biggest win is at the top and the pinned action matches row one.
  List<ScoreComponent> get byOpportunity {
    final list = components.where((c) => c.max > 0).toList()
      ..sort((a, b) {
        final byAvailable = b.available.compareTo(a.available);
        return byAvailable != 0 ? byAvailable : b.max.compareTo(a.max);
      });
    return list;
  }

  /// Components this year mode does not count at all, shown separately so the
  /// student can see *why* something is missing rather than assume a bug.
  List<ScoreComponent> get notCountedThisYear =>
      components.where((c) => c.max == 0).toList();

  factory ReadinessScore.fromRow(Map<String, dynamic> row) {
    final raw =
        (row['components'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReadinessScore(
      total: (row['total'] as num?)?.toInt() ?? 0,
      mode: YearMode.fromWire(row['mode'] as String?),
      components: [
        for (final entry in raw.entries)
          ScoreComponent.fromJson(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
          ),
      ],
      delta: (row['delta'] as num?)?.toInt() ?? 0,
      computedAt:
          DateTime.tryParse('${row['computed_at']}')?.toLocal() ?? _epochValue,
    );
  }
}
