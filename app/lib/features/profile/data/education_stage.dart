/// Where a student is in their education.
///
/// This is the second thing Tack asks and the most consequential: it decides
/// which questions come next, which dashboard they get, and what their score
/// is even measured on.
enum EducationStage {
  primary,
  highSchool,
  bachelors,
  graduated;

  static EducationStage? fromWire(String? value) => switch (value) {
    'primary' => EducationStage.primary,
    'high_school' => EducationStage.highSchool,
    'bachelors' => EducationStage.bachelors,
    'graduated' => EducationStage.graduated,
    _ => null,
  };

  String get wire => switch (this) {
    EducationStage.primary => 'primary',
    EducationStage.highSchool => 'high_school',
    EducationStage.bachelors => 'bachelors',
    EducationStage.graduated => 'graduated',
  };

  String get label => switch (this) {
    EducationStage.primary => 'Primary or middle school',
    EducationStage.highSchool => 'High school or college',
    EducationStage.bachelors => 'Doing a bachelor\'s degree',
    EducationStage.graduated => 'Already graduated',
  };

  String get blurb => switch (this) {
    EducationStage.primary => 'Up to about class 8',
    EducationStage.highSchool => 'SSC, HSC, A levels or equivalent',
    EducationStage.bachelors => 'At university now',
    EducationStage.graduated => 'Finished, looking for work',
  };

  /// Tack has nothing useful for a primary student yet, and pretending
  /// otherwise would waste their time. Everyone else goes forward.
  bool get isSupported => this != EducationStage.primary;

  /// School students are asked about subjects and what they want to study.
  /// Everyone else is asked about a degree.
  bool get isAtSchool => this == EducationStage.highSchool;

  /// A graduate has no year of study left to ask about.
  bool get isStudying =>
      this == EducationStage.highSchool || this == EducationStage.bachelors;
}

/// A country, used for the city list and the phone prefix.
class Country {
  const Country({
    required this.id,
    required this.iso2,
    required this.name,
    required this.dialCode,
  });

  final String id;
  final String iso2;
  final String name;
  final String dialCode;

  factory Country.fromRow(Map<String, dynamic> row) => Country(
    id: row['id'] as String,
    iso2: row['iso2'] as String,
    name: row['name'] as String,
    dialCode: row['dial_code'] as String,
  );
}

/// One thing a student said they like: a subject, a course, a hobby.
enum InterestKind {
  favouriteSubject,
  hobby,
  interest,
  course,
  favouriteCourse;

  static InterestKind fromWire(String? value) => switch (value) {
    'favourite_subject' => InterestKind.favouriteSubject,
    'hobby' => InterestKind.hobby,
    'interest' => InterestKind.interest,
    'course' => InterestKind.course,
    'favourite_course' => InterestKind.favouriteCourse,
    _ => InterestKind.interest,
  };

  String get wire => switch (this) {
    InterestKind.favouriteSubject => 'favourite_subject',
    InterestKind.hobby => 'hobby',
    InterestKind.interest => 'interest',
    InterestKind.course => 'course',
    InterestKind.favouriteCourse => 'favourite_course',
  };
}

class StudentInterest {
  const StudentInterest({
    required this.id,
    required this.kind,
    required this.label,
  });

  final String id;
  final InterestKind kind;
  final String label;

  factory StudentInterest.fromRow(Map<String, dynamic> row) => StudentInterest(
    id: row['id'] as String,
    kind: InterestKind.fromWire(row['kind'] as String?),
    label: row['label'] as String,
  );
}
