import '../../../routing/routes.dart';
import '../data/coach_models.dart';

/// Where a coach chip goes (C7.2). Opened with `tackOpen`, so a tab location
/// switches tabs and anything else is pushed over the bar.
///
/// Null for a route this build does not know: a newer server can add one and
/// an older app simply draws no chip for it.
String? coachDestination(CoachAction action) => switch (action.route) {
  'interview' => Routes.interview,
  'practice' => Routes.interviewReview,
  'analyser' => Routes.analyser,
  'cv_check' => Routes.cvCheck,
  'cv_builder' => Routes.cvBuilder,
  'roadmap' => Routes.roadmap,
  'radar' => Routes.radar,
  'score' => Routes.score,
  'paths' => Routes.paths,
  'path' => switch (action.slug) {
    final slug? when CoachAction.slugPattern.hasMatch(slug) => Routes.path(
      slug,
    ),
    _ => Routes.paths,
  },
  'applications' => Routes.applications,
  'profile' => Routes.profile,
  _ => null,
};
