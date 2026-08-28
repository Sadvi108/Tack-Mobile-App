import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile.dart';
import '../data/profile_repository.dart';
import '../data/profile_sections.dart';
import '../data/profile_sections_repository.dart';

/// How complete a profile is, and — more usefully — which two things to do
/// about it.
///
/// The banner names the missing pieces rather than only showing a percentage,
/// so it reads as a to-do rather than a scolding.
class ProfileCompleteness {
  const ProfileCompleteness({required this.percent, required this.missing});

  final int percent;

  /// Ordered by how much they matter, longest pole first.
  final List<String> missing;

  /// The two the banner names. Two is enough to act on; five is a wall.
  List<String> get topTwo => missing.take(2).toList();

  bool get isComplete => missing.isEmpty;

  String get sentence {
    if (isComplete) return 'Your profile is complete.';
    final two = topTwo;
    if (two.length == 1) return 'One thing left: ${two.first}.';
    return 'Two things left: ${two.first}, and ${two.last}.';
  }
}

ProfileCompleteness computeCompleteness({
  required Profile profile,
  required Map<ProfileSection, List<ProfileEntry>> sections,
  required int skillCount,
}) {
  bool has(ProfileSection section) =>
      (sections[section] ?? const []).isNotEmpty;

  final atSchool = profile.stage?.isAtSchool ?? false;

  // Each item is worth the same. Weighting these would duplicate the readiness
  // score, which already exists and is the number students are meant to watch.
  //
  // What is asked differs by stage: a school student has no internship to add
  // and no target role to pick, and counting either against them would make
  // their profile permanently incomplete for questions nobody asked.
  final checks = <(bool done, String label)>[
    (profile.fullName?.isNotEmpty ?? false, 'add your name'),
    (profile.countryId != null, 'add your country'),
    (profile.cityId != null, 'add your city'),
    (profile.phone?.isNotEmpty ?? false, 'add your phone number'),
    (profile.stage != null, 'say where you are in your education'),
    (has(ProfileSection.education), 'add where you study'),
    if (atSchool) ...[
      (profile.intendedField != null, 'say what you want to study'),
      (has(ProfileSection.favourites), 'add your favourite subjects'),
      (has(ProfileSection.hobbies), 'add what you do outside class'),
    ] else ...[
      (profile.targetRole != null, 'pick a target role'),
      (skillCount >= 5, 'add a few more skills'),
      (has(ProfileSection.experience), 'add an internship or job'),
    ],
    (has(ProfileSection.projects), 'add a project'),
    (has(ProfileSection.activities), 'add a club or competition'),
    (has(ProfileSection.certifications), 'add a certificate'),
    (has(ProfileSection.portfolio), 'add your GitHub or LinkedIn'),
  ];

  final done = checks.where((c) => c.$1).length;
  return ProfileCompleteness(
    percent: (done * 100 / checks.length).round(),
    missing: [
      for (final check in checks)
        if (!check.$1) check.$2,
    ],
  );
}

final completenessProvider = FutureProvider<ProfileCompleteness?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  final sections = await ref.watch(profileSectionsProvider.future);
  final skills = await ref.watch(userSkillsProvider.future);
  return computeCompleteness(
    profile: profile,
    sections: sections,
    skillCount: skills.length,
  );
});
