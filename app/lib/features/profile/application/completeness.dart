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
  // Each item is worth the same. Weighting these would duplicate the readiness
  // score, which already exists and is the number students are meant to watch.
  final checks = <(bool done, String label)>[
    (profile.fullName?.isNotEmpty ?? false, 'add your name'),
    (profile.cityId != null, 'add your city'),
    (profile.phone?.isNotEmpty ?? false, 'add your phone number'),
    (profile.yearOfStudy != null, 'say which year you are in'),
    (profile.targetRole != null, 'pick a target role'),
    ((sections[ProfileSection.education] ?? const []).isNotEmpty, 'add your education'),
    (skillCount >= 5, 'add a few more skills'),
    ((sections[ProfileSection.projects] ?? const []).isNotEmpty, 'add a project'),
    ((sections[ProfileSection.experience] ?? const []).isNotEmpty,
        'add an internship or job'),
    ((sections[ProfileSection.activities] ?? const []).isNotEmpty,
        'add a club or competition'),
    ((sections[ProfileSection.certifications] ?? const []).isNotEmpty,
        'add a certificate'),
    ((sections[ProfileSection.portfolio] ?? const []).isNotEmpty,
        'add your GitHub or LinkedIn'),
  ];

  final done = checks.where((c) => c.$1).length;
  return ProfileCompleteness(
    percent: (done * 100 / checks.length).round(),
    missing: [for (final check in checks) if (!check.$1) check.$2],
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
