/// The four modes the app runs in, derived server-side from year of study.
///
/// This is the single most important value per user: it decides what every
/// dashboard leads with and what language the app uses.
enum YearMode {
  explore,
  build,
  prove,
  launch;

  static YearMode fromWire(String? value) =>
      YearMode.values.firstWhere((m) => m.name == value, orElse: () => YearMode.explore);

  String get label => switch (this) {
        YearMode.explore => 'Explore',
        YearMode.build => 'Build',
        YearMode.prove => 'Prove',
        YearMode.launch => 'Launch',
      };

  /// What the mode chip says above the greeting.
  String get chipText => switch (this) {
        YearMode.explore => 'First year · explore',
        YearMode.build => 'Second year · build',
        YearMode.prove => 'Third year · prove',
        YearMode.launch => 'Final year · launch',
      };

  /// How the student's own cohort is named in score copy. Never compared
  /// against final-years.
  String get cohortNoun => switch (this) {
        YearMode.explore => 'first-years',
        YearMode.build => 'second-years',
        YearMode.prove => 'third-years',
        YearMode.launch => 'final-years',
      };

  /// Applications only become the point of the app in final year.
  bool get showsFunnel => this == YearMode.launch;
}

class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.cityId,
    this.cityName,
    this.phone,
    this.avatarUrl,
    this.yearOfStudy,
    this.yearsTotal,
    this.expectedGraduation,
    this.mode = YearMode.explore,
    this.targetRole,
    this.targetIndustry = const [],
    this.onboardingStep = 0,
    this.onboardingCompletedAt,
  });

  final String id;
  final String? fullName;
  final String? cityId;
  final String? cityName;
  final String? phone;
  final String? avatarUrl;
  final int? yearOfStudy;
  final int? yearsTotal;
  final DateTime? expectedGraduation;
  final YearMode mode;
  final String? targetRole;
  final List<String> targetIndustry;
  final int onboardingStep;
  final DateTime? onboardingCompletedAt;

  bool get hasFinishedOnboarding => onboardingCompletedAt != null;

  /// Two letters for the header avatar. Falls back to a dash rather than an
  /// empty circle when the name is not known yet.
  String get initials {
    final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '–';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String get firstName {
    final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? 'there' : parts.first;
  }

  factory Profile.fromRow(Map<String, dynamic> row) {
    final city = row['cities'];
    return Profile(
      id: row['id'] as String,
      fullName: row['full_name'] as String?,
      cityId: row['city_id'] as String?,
      cityName: city is Map<String, dynamic> ? city['name'] as String? : null,
      phone: row['phone'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      yearOfStudy: row['year_of_study'] as int?,
      yearsTotal: row['years_total'] as int?,
      expectedGraduation: _date(row['expected_graduation']),
      mode: YearMode.fromWire(row['mode'] as String?),
      targetRole: row['target_role'] as String?,
      targetIndustry: (row['target_industry'] as List?)?.cast<String>() ?? const [],
      onboardingStep: (row['onboarding_step'] as int?) ?? 0,
      onboardingCompletedAt: _date(row['onboarding_completed_at']),
    );
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  Profile copyWith({
    String? fullName,
    String? cityId,
    String? cityName,
    String? phone,
    int? yearOfStudy,
    int? yearsTotal,
    DateTime? expectedGraduation,
    String? targetRole,
    List<String>? targetIndustry,
    int? onboardingStep,
    DateTime? onboardingCompletedAt,
  }) =>
      Profile(
        id: id,
        fullName: fullName ?? this.fullName,
        cityId: cityId ?? this.cityId,
        cityName: cityName ?? this.cityName,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl,
        yearOfStudy: yearOfStudy ?? this.yearOfStudy,
        yearsTotal: yearsTotal ?? this.yearsTotal,
        expectedGraduation: expectedGraduation ?? this.expectedGraduation,
        mode: mode,
        targetRole: targetRole ?? this.targetRole,
        targetIndustry: targetIndustry ?? this.targetIndustry,
        onboardingStep: onboardingStep ?? this.onboardingStep,
        onboardingCompletedAt: onboardingCompletedAt ?? this.onboardingCompletedAt,
      );
}
