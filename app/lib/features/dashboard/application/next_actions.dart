import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../roadmap/data/roadmap_models.dart';
import '../../roadmap/data/roadmap_repository.dart';
import '../../score/data/readiness.dart';
import '../../score/data/score_repository.dart';

/// One row of "Your next three actions".
///
/// Each names its point value, so the score and the to-do list explain each
/// other: a student can see that uploading a CV is worth nine points, and the
/// score stops being a mystery number.
class NextAction {
  const NextAction({
    required this.title,
    required this.points,
    required this.effortMinutes,
    required this.route,
    this.taskId,
    this.componentKey,
  });

  final String title;
  final int points;
  final int effortMinutes;
  final String route;

  /// Set when this row is a roadmap task, so it can be ticked in place.
  final String? taskId;

  /// Set when this row is a score component rather than a task.
  final String? componentKey;

  bool get isTask => taskId != null;

  /// Points per hour of effort. Ranking by this rather than by raw points
  /// means a student with twenty spare minutes is pointed at something that
  /// fits, instead of at a three-month project worth more in total.
  double get value => points * 60 / effortMinutes.clamp(1, 100000);
}

/// Ranks everything a student could usefully do next and returns the top few.
///
/// Components the student's year mode does not count are excluded entirely.
/// In explore mode applications are weighted zero on purpose, and telling a
/// first-year to apply for jobs would contradict the whole product.
List<NextAction> rankNextActions({
  required ReadinessScore score,
  required List<Roadmap> roadmaps,
  int limit = 3,
}) {
  final candidates = <NextAction>[
    for (final component in score.opportunities)
      NextAction(
        title: component.action,
        points: component.available,
        effortMinutes: component.effortMinutes,
        route: component.route,
        componentKey: component.key,
      ),
    for (final roadmap in roadmaps)
      for (final milestone in roadmap.milestones)
        if (milestone.state == MilestoneState.active)
          for (final task in milestone.tasks)
            if (!task.isDone)
              NextAction(
                title: task.title,
                points: task.points,
                effortMinutes: task.estMinutes ?? 45,
                route: '/roadmap',
                taskId: task.id,
              ),
  ];

  candidates.sort((a, b) {
    // An overdue-feeling small win first: value per hour, then raw points as
    // the tie-break so two equally efficient actions order sensibly.
    final byValue = b.value.compareTo(a.value);
    return byValue != 0 ? byValue : b.points.compareTo(a.points);
  });

  // One row per distinct thing to do. Two components can legitimately share a
  // destination — "fill in your profile" and "add a few more skills" both land
  // on the profile screen — and they are still different advice, so the key is
  // the action itself, not where it goes.
  final seen = <String>{};
  final picked = <NextAction>[];
  for (final action in candidates) {
    final key = action.taskId ?? action.componentKey ?? action.route;
    if (!seen.add(key)) continue;
    picked.add(action);
    if (picked.length == limit) break;
  }
  return picked;
}

final nextActionsProvider = FutureProvider<List<NextAction>>((ref) async {
  final score = await ref.watch(readinessProvider.future);
  final roadmaps = await ref.watch(roadmapsProvider.future);
  return rankNextActions(score: score, roadmaps: roadmaps);
});
