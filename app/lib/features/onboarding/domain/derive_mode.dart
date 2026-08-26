import '../../profile/data/education_stage.dart';
import '../../profile/data/profile.dart';

/// The mode a student is in, derived from what they told us.
///
/// Never stored as a value. If a student corrects their graduation year the
/// mode has to follow, and a stored string goes stale silently — everything
/// keeps working and everything is subtly misaddressed.
///
/// This mirrors `public.derive_mode` in the database exactly, and a test
/// checks the two agree across every combination rather than trusting them to
/// stay in step.
YearMode deriveMode({
  required EducationStage? stage,
  int? yearOfStudy,
  int? yearsTotal,
  int? graduationYear,
  int? graduationMonth,
  DateTime? now,
}) {
  // Nothing about school depends on a year.
  if (stage == EducationStage.primary || stage == EducationStage.highSchool) {
    return YearMode.discover;
  }
  if (stage == EducationStage.graduated) return YearMode.launch;

  // A graduation date that has already passed outranks the stated stage.
  // People finish a degree and never come back to update the dropdown.
  if (graduationYear != null) {
    final today = now ?? DateTime.now();
    final graduation = DateTime(graduationYear, graduationMonth ?? 12);
    if (graduation.isBefore(DateTime(today.year, today.month))) {
      return YearMode.launch;
    }
  }

  if (yearOfStudy == null) return YearMode.explore;

  // Final year is relative to the programme: year 4 of 4 is launch, year 4 of
  // 5 is still prove.
  if (yearsTotal != null && yearOfStudy >= yearsTotal) return YearMode.launch;

  return switch (yearOfStudy) {
    1 => YearMode.explore,
    2 => YearMode.build,
    _ => YearMode.prove,
  };
}

/// Whether a birth year means the person is too young for Tack to hold data
/// on them at all.
///
/// Thirteen is the line, and it is drawn on the generous side: somebody who
/// turns thirteen later this year is treated as twelve, because being wrong in
/// the other direction means holding personal data on a child.
bool isUnderThirteen({required int? birthYear, DateTime? now}) {
  if (birthYear == null) return false;
  final today = now ?? DateTime.now();
  return today.year - birthYear < 13;
}

/// Age bands, offered as an alternative to a birth year for anyone who would
/// rather not give one.
enum AgeBand {
  under13,
  from13to15,
  from16to18,
  from19to22,
  from23to26,
  over27;

  static AgeBand? fromWire(String? value) => switch (value) {
    'under_13' => AgeBand.under13,
    '13_15' => AgeBand.from13to15,
    '16_18' => AgeBand.from16to18,
    '19_22' => AgeBand.from19to22,
    '23_26' => AgeBand.from23to26,
    '27_plus' => AgeBand.over27,
    _ => null,
  };

  String get wire => switch (this) {
    AgeBand.under13 => 'under_13',
    AgeBand.from13to15 => '13_15',
    AgeBand.from16to18 => '16_18',
    AgeBand.from19to22 => '19_22',
    AgeBand.from23to26 => '23_26',
    AgeBand.over27 => '27_plus',
  };

  String get label => switch (this) {
    AgeBand.under13 => 'Under 13',
    AgeBand.from13to15 => '13 to 15',
    AgeBand.from16to18 => '16 to 18',
    AgeBand.from19to22 => '19 to 22',
    AgeBand.from23to26 => '23 to 26',
    AgeBand.over27 => '27 or older',
  };

  bool get isUnderThirteen => this == AgeBand.under13;
}
