import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../applications/data/application_models.dart';
import '../../applications/data/application_repository.dart';
import '../../paths/data/path_repository.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../../roadmap/data/roadmap_models.dart';
import '../../roadmap/data/roadmap_repository.dart';
import '../../score/data/readiness.dart';
import '../../score/data/score_repository.dart';
import '../../vault/data/document_models.dart';
import '../../vault/data/document_repository.dart';
import 'next_actions.dart';

/// Everything the dashboard draws, resolved together.
///
/// The screen used to read six providers separately and fall back to an empty
/// value on each, which meant a student who had just signed up watched a
/// screen full of confident zeros while their real score was still in flight.
/// One future gives the screen three honest states instead of a permanent
/// optimistic guess.
class DashboardData {
  const DashboardData({
    required this.profile,
    required this.score,
    required this.weekChange,
    required this.cohort,
    required this.actions,
    required this.setupSteps,
    required this.roadmaps,
    required this.counts,
    required this.upcoming,
    required this.documents,
    required this.chosenPaths,
  });

  final Profile profile;
  final ReadinessScore score;
  final int weekChange;
  final CohortBenchmark? cohort;
  final List<NextAction> actions;

  /// The remaining first-run steps, empty once the student is set up.
  final List<NextAction> setupSteps;

  final List<Roadmap> roadmaps;
  final ApplicationCounts counts;
  final List<JobApplication> upcoming;
  final List<TackDocument> documents;
  final List<ChosenPath> chosenPaths;

  YearMode get mode => profile.mode;

  /// How many of the areas that count in this mode have any score at all.
  ///
  /// A component weighted zero for this student is not an area they are
  /// failing at — it is a question nobody asked them — so it is left out of
  /// both halves of the fraction.
  int get areasCounted => score.components.where((c) => c.max > 0).length;
  int get areasScored =>
      score.components.where((c) => c.max > 0 && c.earned > 0).length;

  bool get isSetUp => setupSteps.isEmpty;
}

final dashboardProvider = FutureProvider<DashboardData?>((ref) async {
  // Every dependency is watched synchronously, before the first await.
  //
  // This is not style. `ref.watch` after an await does not register the
  // dependency properly and the provider never settles — the screen sat on its
  // loading skeleton forever. Collecting the futures first also means the nine
  // reads happen at once rather than one after another.
  final profileFuture = ref.watch(profileProvider.future);
  final scoreFuture = ref.watch(readinessProvider.future);
  final weekChangeFuture = ref.watch(weekChangeProvider.future);
  final cohortFuture = ref.watch(cohortProvider.future);
  final roadmapsFuture = ref.watch(roadmapsProvider.future);
  final documentsFuture = ref.watch(documentsProvider.future);
  final chosenFuture = ref.watch(chosenPathsProvider.future);
  final countsFuture = ref.watch(applicationCountsProvider.future);
  final upcomingFuture = ref.watch(upcomingApplicationsProvider.future);

  final profile = await profileFuture;
  if (profile == null) return null;

  final score = await scoreFuture;
  final roadmaps = await roadmapsFuture;
  final documents = await documentsFuture;
  final chosen = await chosenFuture;
  final counts = await countsFuture;

  return DashboardData(
    profile: profile,
    score: score,
    weekChange: await weekChangeFuture,
    cohort: await cohortFuture,
    actions: rankNextActions(score: score, roadmaps: roadmaps),
    setupSteps: setupSteps(
      score: score,
      documents: documents,
      chosenPaths: chosen,
      applicationCount: counts.total,
    ),
    roadmaps: roadmaps,
    counts: counts,
    upcoming: await upcomingFuture,
    documents: documents,
    chosenPaths: chosen,
  );
});

/// What a student still has to do before Tack can be useful to them.
///
/// Deliberately computed rather than a fixed list. The eight onboarding
/// questions are already answered by the time anyone reaches this screen — the
/// flow will not let them past — so printing "answer 8 questions" as step one
/// would show every real student a step they finished minutes ago.
///
/// Points come from the score engine rather than being written here, so the
/// card and the score can never disagree about what something is worth.
List<NextAction> setupSteps({
  required ReadinessScore score,
  required List<TackDocument> documents,
  required List<ChosenPath> chosenPaths,
  required int applicationCount,
}) {
  int worth(String component) => score.components
      .where((c) => c.key == component)
      .fold(0, (_, c) => c.available);

  bool counts(String component) =>
      score.components.any((c) => c.key == component && c.max > 0);

  final hasCv = documents.any(
    (d) => d.type == DocumentType.cv && d.status != DocumentStatus.failed,
  );

  return [
    if (!hasCv)
      NextAction(
        title: 'Upload your CV',
        points: worth('cv_quality'),
        effortMinutes: 1,
        route: '/vault',
        componentKey: 'cv_quality',
      ),
    if (chosenPaths.isEmpty)
      NextAction(
        title: 'Pick a target job',
        // Choosing a path does not score directly; it builds the roadmap that
        // everything else hangs off, which is why it is worth saying so rather
        // than showing a number.
        points: 0,
        effortMinutes: 1,
        route: '/paths',
      ),
    // Never shown to a first-year: application activity is weighted zero in
    // explore mode on purpose, and telling them to apply for jobs would
    // contradict the whole product.
    if (applicationCount == 0 && counts('application_activity'))
      NextAction(
        title: 'Add your first application',
        points: worth('application_activity'),
        effortMinutes: 2,
        route: '/applications',
        componentKey: 'application_activity',
      ),
  ];
}
