export '../data/dashboard_repository.dart' show dashboardFeedProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../applications/data/application_models.dart';
import '../../profile/data/profile.dart';
import '../../score/data/readiness.dart';
import '../data/dashboard_feed.dart';
import '../data/dashboard_repository.dart';
import 'insights.dart';
import 'next_actions.dart';

/// Everything the dashboard draws, resolved together.
///
/// This used to compose nine providers and fall back to an empty value on
/// each, which meant a student who had just signed up watched a screen full of
/// confident zeros while their real score was still in flight. It then became
/// one composed future, which fixed the honesty problem but kept the nine
/// round trips.
///
/// It is now one RPC. The database assembles the snapshot, so every card on
/// the screen is describing the same moment — the roadmap card and the
/// timeline can no longer disagree about whether a task is done.
///
/// What stays on the client is the ranking and the wording: which suggestion
/// leads, and how it is phrased for this student's year. That is product
/// judgement, it changes far more often than the schema, and it is where the
/// tests are.
class DashboardData {
  const DashboardData({
    required this.feed,
    required this.actions,
    required this.setupSteps,
    required this.insights,
  });

  final DashboardFeed feed;

  /// The ranked "next three actions", best value for time first.
  final List<NextAction> actions;

  /// The remaining first-run steps, empty once the student is set up.
  final List<NextAction> setupSteps;

  /// The suggestion deck.
  final List<Insight> insights;

  Profile get profile => feed.profile;
  ReadinessScore get score => feed.score;
  YearMode get mode => feed.mode;
  int get weekChange => feed.weekChange;
  ApplicationCounts get counts => feed.counts;
  Streak get streak => feed.streak;
  RoadmapSummary get roadmap => feed.roadmap;

  int get areasCounted => feed.areasCounted;
  int get areasScored => feed.areasScored;

  bool get isSetUp => setupSteps.isEmpty;

  /// The timeline, filtered to what this year mode is allowed to be told
  /// about. A first-year is never shown a closing date or a follow-up.
  List<TimelineEntry> get timeline {
    final jobsAreRelevant = mode.showsFunnel || mode == YearMode.prove;
    return feed.timeline
        .where((e) => jobsAreRelevant || e.kind == TimelineKind.task)
        .toList(growable: false);
  }

  List<TimelineEntry> get overdue =>
      timeline.where((e) => e.isOverdue).toList(growable: false);
  List<TimelineEntry> get upcoming =>
      timeline.where((e) => !e.isOverdue).toList(growable: false);

  factory DashboardData.from(DashboardFeed feed) => DashboardData(
    feed: feed,
    actions: rankNextActions(
      score: feed.score,
      roadmaps: const [],
      nextTaskId: feed.roadmap.nextTaskId,
      nextTaskTitle: feed.roadmap.nextTaskTitle,
      nextTaskPoints: feed.roadmap.nextTaskPoints,
      nextTaskMinutes: feed.roadmap.nextTaskMinutes,
    ),
    setupSteps: remainingSetupSteps(
      score: feed.score,
      hasCv: feed.hasCv,
      chosenPathCount: feed.chosenPaths,
      applicationCount: feed.counts.total,
    ),
    insights: buildInsights(feed),
  );
}

final dashboardProvider = FutureProvider<DashboardData?>((ref) async {
  final feed = await ref.watch(dashboardFeedProvider.future);
  return feed == null ? null : DashboardData.from(feed);
});

/// What a student still has to do before Tack can be useful to them.
///
/// Deliberately computed rather than a fixed list. The onboarding questions
/// are already answered by the time anyone reaches this screen — the flow will
/// not let them past — so printing "answer 8 questions" as step one would show
/// every real student a step they finished minutes ago.
///
/// Points come from the score engine rather than being written here, so the
/// card and the score can never disagree about what something is worth.
List<NextAction> remainingSetupSteps({
  required ReadinessScore score,
  required bool hasCv,
  required int chosenPathCount,
  required int applicationCount,
}) {
  int worth(String component) => score.components
      .where((c) => c.key == component)
      .fold(0, (_, c) => c.available);

  bool counts(String component) =>
      score.components.any((c) => c.key == component && c.max > 0);

  return [
    // `hasCv` comes from the feed, which excludes a failed upload and includes
    // one still being read: a CV Tack is halfway through parsing is already
    // uploaded, and asking for it again would be wrong.
    if (!hasCv)
      NextAction(
        title: 'Upload your CV',
        points: worth('cv_quality'),
        effortMinutes: 1,
        route: '/vault',
        componentKey: 'cv_quality',
      ),
    if (chosenPathCount == 0)
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
