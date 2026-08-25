import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../applications/data/application_models.dart';
import '../../applications/data/application_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../../roadmap/data/roadmap_models.dart';
import '../../roadmap/data/roadmap_repository.dart';
import '../../score/data/readiness.dart';
import '../../score/data/score_repository.dart';
import '../application/next_actions.dart';
import 'widgets.dart';

/// The home screen, in four flavours.
///
/// Same components, four priorities. The mode comes from the student's year of
/// study and decides what leads, what is hidden, and which words are used.
/// A first-year is never shown a funnel or told about a deadline.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const _DashboardLoading(),
      error: (_, _) => TackScaffold(
        bottomNav: const _Nav(mode: YearMode.explore),
        header: const TackHomeHeader(initials: '–'),
        body: TackErrorState(
          body:
              'Your dashboard did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
      data: (profile) {
        if (profile == null) return const _DashboardLoading();
        return _Dashboard(profile: profile);
      },
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = profile.mode;
    final score = ref.watch(readinessProvider).value ?? ReadinessScore.empty;
    final weekChange = ref.watch(weekChangeProvider).value ?? 0;
    final cohort = ref.watch(cohortProvider).value;
    final actions =
        ref.watch(nextActionsProvider).value ?? const <NextAction>[];
    final roadmaps = ref.watch(roadmapsProvider).value ?? const <Roadmap>[];
    final online = ref.watch(isOnlineProvider);
    final queued = ref.watch(pendingChangesProvider).value ?? 0;

    Future<void> refresh() async {
      ref.invalidate(profileProvider);
      ref.invalidate(readinessProvider);
      ref.invalidate(weekChangeProvider);
      ref.invalidate(roadmapsProvider);
      ref.invalidate(applicationCountsProvider);
      ref.invalidate(upcomingApplicationsProvider);
    }

    return TackScaffold(
      // The body brings its own ListView so it can pull to refresh; the shell
      // must not wrap it in a second scroll view.
      scrollable: false,
      bottomNav: _Nav(mode: mode),
      header: TackHomeHeader(
        initials: profile.initials,
        unread: ref.watch(unreadCountProvider),
        onAvatarTap: () => context.go(Routes.profile),
        onBellTap: () => context.push(Routes.notifications),
      ),
      body: RefreshIndicator(
        color: TackColors.maroon,
        onRefresh: refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!online) ...[
              TackOfflineState(queuedChanges: queued),
              const SizedBox(height: TackSpace.stackLoose),
            ],
            ModeChip(mode),
            const SizedBox(height: TackSpace.md),
            Text('Hi ${profile.firstName}', style: TackText.screenTitle),
            const SizedBox(height: TackSpace.xs),
            Text(_greeting(mode), style: TackText.bodyMuted),
            const SizedBox(height: TackSpace.lg),

            // Explore mode leads with a path CTA rather than a score, because a
            // first-year's problem is not knowing what to aim at.
            if (mode == YearMode.explore) ...[
              _ExploreCta(onTap: () => context.go(Routes.paths)),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // Final year leads with dates. Urgency is appropriate here and
            // nowhere else.
            if (mode == YearMode.launch) ...[
              const _SevenDayCard(),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            ScoreSummaryCard(
              score: score.total,
              weekChange: weekChange,
              mode: mode,
              cohort: cohort,
              onTap: () => context.go(Routes.score),
            ),
            const SizedBox(height: TackSpace.stackLoose),

            NextThreeActions(
              actions: actions,
              heading: mode == YearMode.explore
                  ? 'Try these this month'
                  : 'Your next three actions',
              onOpen: (action) => context.go(action.route),
              onTickTask: (action) async {
                await ref
                    .read(roadmapRepositoryProvider)
                    .setTaskDone(action.taskId!, done: true);
                ref.invalidate(roadmapsProvider);
                ref.invalidate(readinessProvider);
                if (context.mounted) {
                  TackToast.show(
                    context,
                    message: 'Done. +${action.points} points.',
                  );
                }
              },
            ),
            const SizedBox(height: TackSpace.stackLoose),

            if (roadmaps.isNotEmpty) ...[
              _RoadmapProgressCard(
                roadmaps: roadmaps,
                onTap: () => context.go(Routes.roadmap),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // The funnel exists only in final year. Junior years never see it.
            if (mode.showsFunnel) ...[
              const _Funnel(),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            const SizedBox(height: TackSpace.xl),
          ],
        ),
      ),
    );
  }

  static String _greeting(YearMode mode) => switch (mode) {
    YearMode.school =>
      'No rush at all. Find out what you are good at and what you enjoy.',
    YearMode.graduate => 'Let us get you hired.',
    YearMode.explore =>
      'There is no rush this year. Look around and try a few things.',
    YearMode.build => 'This is the year skills start to add up.',
    YearMode.prove => 'Time to show what you can do, and to meet people.',
    YearMode.launch => 'Let us get you hired.',
  };
}

class _ExploreCta extends StatelessWidget {
  const _ExploreCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: TackColors.maroon,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore career paths',
            style: TackText.sectionHeader.copyWith(color: TackColors.white),
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            'Ten real jobs, what they pay in Bangladesh, and what it takes to get one. '
            'Nothing to commit to.',
            style: TackText.bodyMuted.copyWith(color: const Color(0xD1FFFFFF)),
          ),
          const SizedBox(height: TackSpace.lg),
          TackButton.amber('Have a look', onPressed: onTap),
        ],
      ),
    );
  }
}

class _SevenDayCard extends ConsumerWidget {
  const _SevenDayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming =
        ref.watch(upcomingApplicationsProvider).value ??
        const <JobApplication>[];

    return TackCard(
      background: TackColors.maroon,
      onTap: () => context.go(Routes.applications),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next seven days',
            style: TackText.cardTitle.copyWith(color: TackColors.white),
          ),
          const SizedBox(height: TackSpace.md),
          if (upcoming.isEmpty)
            Text(
              'Nothing due this week. A good week to add two applications.',
              style: TackText.bodyMuted.copyWith(
                color: const Color(0xD1FFFFFF),
              ),
            )
          else
            for (final application in upcoming.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: TackSpace.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        _relativeDay(application.daysUntilNextAction),
                        style: TackText.pill.copyWith(color: TackColors.amber),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        application.nextAction ?? application.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TackText.body.copyWith(
                          color: TackColors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _relativeDay(int? days) => switch (days) {
    null => '',
    < 0 => 'Overdue',
    0 => 'Today',
    1 => 'Tomorrow',
    _ => 'In $days d',
  };
}

class _Funnel extends ConsumerWidget {
  const _Funnel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts =
        ref.watch(applicationCountsProvider).value ?? ApplicationCounts.empty;
    return ApplicationFunnel(
      counts: counts.asWireMap,
      onTap: () => context.go(Routes.applications),
    );
  }
}

class _RoadmapProgressCard extends StatelessWidget {
  const _RoadmapProgressCard({required this.roadmaps, required this.onTap});

  final List<Roadmap> roadmaps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = roadmaps.fold(0, (sum, r) => sum + r.doneCount);
    final total = roadmaps.fold(0, (sum, r) => sum + r.totalCount);
    final percent = total == 0 ? 0 : (done * 100 / total).round();

    return TackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Your roadmap', style: TackText.cardTitle)),
              Text(
                '$percent%',
                style: TackText.cardTitle.copyWith(color: TackColors.maroon),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          TackProgressBar(value: total == 0 ? 0 : done / total, height: 8),
          const SizedBox(height: TackSpace.sm),
          Text('$done of $total steps done', style: TackText.meta),
        ],
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.mode});

  final YearMode mode;

  @override
  Widget build(BuildContext context) {
    final tabs = TackTabs.forMode(mode.name);
    return TackBottomNav(
      tabs: tabs,
      currentIndex: 0,
      onTap: (i) => context.go(tabs[i].route),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const TackScaffold(
      header: TackHomeHeader(initials: '–'),
      bottomNav: _Nav(mode: YearMode.explore),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackSkeleton(width: 140, height: 28, radius: 14),
          SizedBox(height: TackSpace.lg),
          TackSkeleton(height: 128, radius: 20),
          SizedBox(height: TackSpace.stackLoose),
          TackSkeleton(height: 190, radius: 20),
        ],
      ),
    );
  }
}
