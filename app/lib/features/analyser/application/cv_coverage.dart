import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analysis_repository.dart';

/// Which of the skills a job wants, and the student has, their CV actually
/// shows.
///
/// Hiring software reads the CV, not the Tack profile. A skill in the profile
/// that the CV never names is invisible to it, and that is the cheapest gap a
/// student can close: no learning, just a line in the right place.
class CvCoverage {
  const CvCoverage({required this.shown, required this.hidden});

  /// Matched skills the latest CV check also found.
  final List<String> shown;

  /// Matched skills the latest CV check did not find.
  final List<String> hidden;
}

/// Splits [matched] by whether the latest CV check found each one.
///
/// Both sides are names from the same skills taxonomy — profile skills are
/// taxonomy rows, and the CV check recognises taxonomy skills — so this is a
/// set comparison, with the same loose equality as `_shared/ai/matching.ts`.
CvCoverage cvCoverage(List<String> matched, List<String> cvSkills) {
  final onCv = {for (final s in cvSkills) _normalise(s)};
  final shown = <String>[];
  final hidden = <String>[];
  for (final skill in matched) {
    (onCv.contains(_normalise(skill)) ? shown : hidden).add(skill);
  }
  return CvCoverage(shown: shown, hidden: hidden);
}

String _normalise(String skill) =>
    skill.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Skills found by the student's latest CV check, or null when they have
/// never run one.
final latestCvSkillsProvider = FutureProvider.autoDispose<List<String>?>(
  (ref) => ref.watch(analysisRepositoryProvider).latestCvSkills(),
);
