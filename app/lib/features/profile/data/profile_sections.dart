/// The records that make up a profile beyond the core fields.
///
/// One small model per section, all shaped the same way so the profile screen
/// can render and edit them through a single widget rather than eight.
library;

class ProfileEntry {
  const ProfileEntry({
    required this.id,
    required this.title,
    this.subtitle,
    this.detail,
    this.meta,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? detail;
  final String? meta;
}

class UserSkill {
  const UserSkill({
    required this.id,
    required this.skillId,
    required this.name,
    required this.proficiency,
    required this.source,
  });

  final String id;
  final String skillId;
  final String name;

  /// 1 to 5. Shown as a bar, never as a number out of five — a student
  /// rating themselves 2/5 should not read as a failing grade.
  final int proficiency;
  final String source;

  String get proficiencyLabel => switch (proficiency) {
    1 => 'Just started',
    2 => 'Getting there',
    3 => 'Comfortable',
    4 => 'Strong',
    _ => 'Could teach it',
  };

  factory UserSkill.fromRow(Map<String, dynamic> row) {
    final skill = (row['skills'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UserSkill(
      id: row['id'] as String,
      skillId: row['skill_id'] as String,
      name: (skill['name'] as String?) ?? 'Unknown skill',
      proficiency: (row['proficiency'] as num?)?.toInt() ?? 2,
      source: (row['source'] as String?) ?? 'self',
    );
  }
}

/// Which sections exist, and what each one is called on screen.
enum ProfileSection {
  education,
  favourites,
  hobbies,
  courses,
  skills,
  projects,
  experience,
  activities,
  certifications,
  portfolio;

  /// What a student at this stage should actually be shown.
  ///
  /// A school student has no courses to list and no CV to attach; an
  /// undergraduate does not need a hobbies section competing with their
  /// skills. Showing every section to everyone would make most of the profile
  /// empty for most people, which reads as failure rather than as not asked.
  static List<ProfileSection> forSchool() => const [
    education,
    favourites,
    hobbies,
    projects,
    activities,
    certifications,
    portfolio,
  ];

  static List<ProfileSection> forUniversity() => const [
    education,
    courses,
    favourites,
    projects,
    experience,
    activities,
    certifications,
    portfolio,
  ];

  String get title => switch (this) {
    ProfileSection.education => 'Education',
    ProfileSection.favourites => 'Favourite subjects',
    ProfileSection.hobbies => 'Outside class',
    ProfileSection.courses => 'Courses',
    ProfileSection.skills => 'Skills',
    ProfileSection.projects => 'Projects',
    ProfileSection.experience => 'Experience',
    ProfileSection.activities => 'Activities',
    ProfileSection.certifications => 'Certificates',
    ProfileSection.portfolio => 'Links',
  };

  String get emptyHint => switch (this) {
    ProfileSection.education => 'Add where you study',
    ProfileSection.favourites => 'Add the subjects you like most',
    ProfileSection.hobbies => 'Add a club, a sport, anything you do',
    ProfileSection.courses => 'Add this semester\'s courses',
    ProfileSection.skills => 'Add what you can do',
    ProfileSection.projects => 'Add something you built',
    ProfileSection.experience => 'Add an internship or job',
    ProfileSection.activities => 'Add a club or competition',
    ProfileSection.certifications => 'Add a certificate you earned',
    ProfileSection.portfolio => 'Add your GitHub or LinkedIn',
  };

  String get table => switch (this) {
    ProfileSection.education => 'education',
    ProfileSection.favourites => 'student_interests',
    ProfileSection.hobbies => 'student_interests',
    ProfileSection.courses => 'courses',
    ProfileSection.skills => 'user_skills',
    ProfileSection.projects => 'projects',
    ProfileSection.experience => 'experiences',
    ProfileSection.activities => 'activities',
    ProfileSection.certifications => 'certifications',
    ProfileSection.portfolio => 'portfolio_links',
  };
}

/// A section's health, shown as a dot: teal when it is in good shape, amber
/// when it is thin, and rose when there is nothing there at all.
enum SectionHealth { empty, thin, good }

SectionHealth healthFor(ProfileSection section, int count) {
  if (count == 0) return SectionHealth.empty;
  final target = switch (section) {
    ProfileSection.education => 1,
    ProfileSection.favourites => 3,
    ProfileSection.hobbies => 2,
    ProfileSection.courses => 4,
    ProfileSection.skills => 8,
    ProfileSection.projects => 2,
    ProfileSection.experience => 1,
    ProfileSection.activities => 2,
    ProfileSection.certifications => 2,
    ProfileSection.portfolio => 2,
  };
  return count >= target ? SectionHealth.good : SectionHealth.thin;
}
