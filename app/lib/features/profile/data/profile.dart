import 'education_stage.dart';

/// The four modes the app runs in, derived server-side from year of study.
///
/// This is the single most important value per user: it decides what every
/// dashboard leads with and what language the app uses.
enum YearMode {
  /// Still at school, choosing what to study rather than where to work.
  school,
  explore,
  build,
  prove,
  launch,

  /// Finished studying and looking for the first job now.
  graduate;

  static YearMode fromWire(String? value) => YearMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => YearMode.explore,
  );

  String get label => switch (this) {
    YearMode.school => 'School',
    YearMode.graduate => 'Launch',
    YearMode.explore => 'Explore',
    YearMode.build => 'Build',
    YearMode.prove => 'Prove',
    YearMode.launch => 'Launch',
  };

  /// What the mode chip says above the greeting.
  String get chipText => switch (this) {
    YearMode.school => 'At school · explore',
    YearMode.graduate => 'Graduated · job hunting',
    YearMode.explore => 'First year · explore',
    YearMode.build => 'Second year · build',
    YearMode.prove => 'Third year · prove',
    YearMode.launch => 'Final year · launch',
  };

  /// How the student's own cohort is named in score copy. Never compared
  /// against final-years.
  String get cohortNoun => switch (this) {
    YearMode.school => 'students your age',
    YearMode.graduate => 'recent graduates',
    YearMode.explore => 'first-years',
    YearMode.build => 'second-years',
    YearMode.prove => 'third-years',
    YearMode.launch => 'final-years',
  };

  /// Applications are only the point of the app once a student is actually
  /// applying — final year, or already graduated.
  bool get showsFunnel => this == YearMode.launch || this == YearMode.graduate;

  /// A school student is choosing a subject, not a job.
  bool get isAtSchool => this == YearMode.school;
}

class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.countryId,
    this.countryName,
    this.dialCode = '+880',
    this.stage,
    this.intendedField,
    this.passion,
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
  final String? countryId;
  final String? countryName;

  /// The phone prefix that goes with the country, so the form never assumes
  /// where a student lives.
  final String dialCode;

  final EducationStage? stage;

  /// What a school student wants to study, and why they care. Their own words.
  final String? intendedField;
  final String? passion;

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
    final parts = (fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '–';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get firstName {
    final parts = (fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    return parts.isEmpty ? 'there' : parts.first;
  }

  factory Profile.fromRow(Map<String, dynamic> row) {
    final city = row['cities'];
    final country = row['countries'];
    return Profile(
      id: row['id'] as String,
      fullName: row['full_name'] as String?,
      countryId: row['country_id'] as String?,
      countryName: country is Map<String, dynamic>
          ? country['name'] as String?
          : null,
      dialCode: country is Map<String, dynamic>
          ? (country['dial_code'] as String?) ?? '+880'
          : '+880',
      stage: EducationStage.fromWire(row['education_stage'] as String?),
      intendedField: row['intended_field'] as String?,
      passion: row['passion'] as String?,
      cityId: row['city_id'] as String?,
      cityName: city is Map<String, dynamic> ? city['name'] as String? : null,
      phone: row['phone'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      yearOfStudy: row['year_of_study'] as int?,
      yearsTotal: row['years_total'] as int?,
      expectedGraduation: _date(row['expected_graduation']),
      mode: YearMode.fromWire(row['mode'] as String?),
      targetRole: row['target_role'] as String?,
      targetIndustry:
          (row['target_industry'] as List?)?.cast<String>() ?? const [],
      onboardingStep: (row['onboarding_step'] as int?) ?? 0,
      onboardingCompletedAt: _date(row['onboarding_completed_at']),
    );
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  Profile copyWith({
    String? fullName,
    String? countryId,
    String? countryName,
    String? dialCode,
    EducationStage? stage,
    String? intendedField,
    String? passion,
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
  }) => Profile(
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
