import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics.dart';
import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../../routing/tab_bar.dart';
import '../../paths/data/path_repository.dart';
import '../../profile/data/profile.dart';
import '../../roadmap/data/roadmap_repository.dart';
import '../application/dashboard_data.dart';
import '../application/insights.dart';
import '../data/dashboard_feed.dart';
import 'insight_deck.dart';
import 'motion.dart';
import 'path_fit_card.dart';
import 'progress_card.dart';
import 'streak_card.dart';
import 'timeline_card.dart';
import 'widgets.dart';

/// The home screen, in six flavours.
///
/// Same components, different priorities. The mode comes from the student's
/// education stage and year and decides what leads, what is hidden, and which
/// words are used. A first-year is never shown a funnel, a closing date or the
/// word "apply" — that is enforced here and checked by a test, not left to
/// whoever writes the next card.
///
/// Everything on the screen is one snapshot from `dashboard_feed()`, so no two
/// cards can disagree about the same fact.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return dashboard.when(
      loading: () => const _DashboardLoading(),
      error: (_, _) => TackScaffold(
        bottomNav: const _Nav(),
        header: const TackHomeHeader(initials: '–'),
        body: TackErrorState(
          body:
              'Your dashboard did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(dashboardFeedProvider),
        ),
      ),
      data: (data) =>
          data == null ? const _DashboardLoading() : _Dashboard(data: data),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = data.feed;
    final profile = data.profile;
    final mode = data.mode;
    final online = ref.watch(isOnlineProvider);
    final queued = ref.watch(pendingChangesProvider).value ?? 0;

    // Final year and graduates lead with dates; nobody else is shown one.
    // Urgency is appropriate exactly once in this app.
    final leadsWithDates = mode.showsFunnel;
    final sevenDays = data.upcoming
        .where((e) => e.daysFrom(feed.today) <= 7)
        .toList();

    Future<void> refresh() async {
      ref.invalidate(dashboardFeedProvider);
      await ref.read(dashboardFeedProvider.future);
    }

    // One counter for the whole screen so the stagger is continuous no matter
    // which cards this mode happens to render.
    //
    // The list itself is unpadded and each card brings its own gutter, so the
    // suggestion deck can run off the right edge while everything else lines
    // up. A deck clipped inside the gutter reads as a rendering bug rather
    // than as "there is another card".
    var step = 0;
    Widget reveal(Widget child) => TackReveal(
      index: step++,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
        child: child,
      ),
    );
    Widget revealFullBleed(Widget child) =>
        TackReveal(index: step++, child: child);
    Widget padded(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
      child: child,
    );

    return TackScaffold(
      // The body brings its own ListView so it can pull to refresh; the shell
      // must not wrap it in a second scroll view.
      scrollable: false,
      bottomNav: const _Nav(),
      // The coach floats over the dashboard rather than taking a tab: the five
      // destinations are full at 360px, and asking a question is something a
      // student does *about* what they are looking at, not instead of it.
      floatingAction: _CoachButton(onTap: () => context.push(Routes.coach)),
      header: TackHomeHeader(
        initials: profile.initials,
        unread: feed.unreadNotifications,
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
              padded(TackOfflineState(queuedChanges: queued)),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModeChip(mode),
                  const SizedBox(height: TackSpace.md),
                  Text('Hi ${profile.firstName}', style: TackText.screenTitle),
                  const SizedBox(height: TackSpace.xs),
                  Text(_greeting(mode), style: TackText.bodyMuted),
                ],
              ),
            ),
            const SizedBox(height: TackSpace.lg),

            // Explore mode leads with a path CTA rather than a score, because
            // a first-year's problem is not knowing what to aim at.
            if (mode == YearMode.explore || mode == YearMode.discover) ...[
              reveal(
                _ExploreCta(
                  available: feed.availablePaths,
                  onTap: () => context.push(Routes.paths),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            if (leadsWithDates) ...[
              reveal(
                _NextSevenDays(
                  entries: sevenDays,
                  overdue: data.overdue,
                  today: feed.today,
                  hasApplications: data.counts.total > 0,
                  onOpen: (entry) => context.push(entry.route),
                  onSeeAll: () => context.go(Routes.applications),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            reveal(
              ReadinessBlock(
                score: data.score.total,
                areasScored: data.areasScored,
                areasCounted: data.areasCounted,
                onSeeBreakdown: () => context.push(Routes.score),
                animated: true,
              ),
            ),
            const SizedBox(height: TackSpace.stackLoose),

            // The deck is the screen's answer to "what should I be doing".
            if (data.insights.isNotEmpty) ...[
              revealFullBleed(
                InsightDeck(
                  insights: data.insights,
                  onOpen: (insight) => _openInsight(context, ref, insight),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // One to-do list at a time. While a student is still setting up,
            // the ranked suggestions would compete with the things that
            // actually have to happen first, so they wait their turn.
            if (!data.isSetUp) ...[
              reveal(
                StartHereCard(
                  steps: data.setupSteps,
                  onOpen: (step) => context.go(step.route),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ] else ...[
              reveal(
                NextThreeActions(
                  actions: data.actions,
                  heading: mode == YearMode.explore || mode == YearMode.discover
                      ? 'Try these this month'
                      : 'Your next three actions',
                  onOpen: (action) => context.go(action.route),
                  onTickTask: (action) async {
                    await ref
                        .read(roadmapRepositoryProvider)
                        .setTaskDone(action.taskId!, done: true);
                    ref.invalidate(dashboardFeedProvider);
                    if (context.mounted) {
                      TackToast.show(
                        context,
                        message: 'Done. +${action.points} points.',
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // Everybody else gets the same dates, without the urgency.
            if (!leadsWithDates && data.timeline.isNotEmpty) ...[
              reveal(
                TimelineCard(
                  entries: [...data.overdue, ...data.upcoming],
                  today: feed.today,
                  onOpen: (entry) => context.push(entry.route),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // A target the student actually chose: show how close they are.
            if (feed.primaryPathTitle case final title?) ...[
              reveal(
                PathFitCard(
                  pathTitle: title,
                  gap: feed.skillGap,
                  held: feed.skillsHeld,
                  asked: feed.skillsAsked,
                  onOpen: () => context.push(
                    feed.primaryPathSlug == null
                        ? Routes.paths
                        : Routes.path(feed.primaryPathSlug!),
                  ),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ]
            // Following something without committing to it. Ask; do not
            // promote a browse into a decision on their behalf.
            else if (feed.following.isNotEmpty) ...[
              reveal(
                NoTargetCard(
                  following: feed.following.first,
                  statedRole: profile.targetRole,
                  onChoose: () async {
                    await ref
                        .read(pathRepositoryProvider)
                        .makePrimary(feed.following.first.id);
                    ref
                      ..invalidate(dashboardFeedProvider)
                      ..invalidate(chosenPathsProvider);
                    if (context.mounted) {
                      TackToast.show(
                        context,
                        message:
                            '${feed.following.first.title} is your target now.',
                      );
                    }
                  },
                  onOpen: () =>
                      context.push(Routes.path(feed.following.first.slug)),
                  onBrowse: () => context.push(Routes.paths),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ]
            // Nothing followed, but they told us what they want to be.
            else if (profile.targetRole case final role?
                when role.trim().isNotEmpty) ...[
              reveal(
                NoTargetCard(
                  statedRole: role,
                  onBrowse: () => context.push(Routes.paths),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            reveal(
              ProgressCard(
                trend: feed.trend,
                weekChange: data.weekChange,
                thisWeek: feed.thisWeek,
                lastWeek: feed.lastWeek,
                onTap: () => context.push(Routes.score),
              ),
            ),
            const SizedBox(height: TackSpace.stackLoose),

            reveal(StreakCard(streak: data.streak, today: feed.today)),
            const SizedBox(height: TackSpace.stackLoose),

            if (data.roadmap.exists) ...[
              reveal(
                _RoadmapProgressCard(
                  roadmap: data.roadmap,
                  onTap: () => context.go(Routes.roadmap),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // The funnel exists only in final year and after. Junior years
            // never see it.
            if (mode.showsFunnel) ...[
              reveal(
                ApplicationFunnel(
                  counts: data.counts.asWireMap,
                  onTap: () => context.go(Routes.applications),
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
            ],

            // Interview practice and the job-description analyser are whole
            // features that nothing in the app navigated to. They had routes
            // and screens and no door: the only way in was a deep link, which
            // is also why their back arrows had never worked.
            reveal(
              padded(
                _GetReady(
                  onInterview: () => context.push(Routes.interview),
                  onAnalyse: () => context.push(Routes.analyser),
                ),
              ),
            ),
            const SizedBox(height: TackSpace.stackLoose),

            padded(const PrivacyNote()),
            const SizedBox(height: TackSpace.xl),
          ],
        ),
      ),
    );
  }

  /// Opening a suggestion records which one, and nothing about it. The card's
  /// id is a fixed slug — never its title, which can carry a job title or a
  /// student's own words for a milestone.
  void _openInsight(BuildContext context, WidgetRef ref, Insight insight) {
    final route = insight.route;
    if (route == null) return;
    ref
        .read(analyticsProvider)
        .track(
          'insight_opened',
          properties: {'insight': insight.id, 'tone': insight.tone.name},
        );
    context.push(route);
  }

  static String _greeting(YearMode mode) => switch (mode) {
    YearMode.discover =>
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
  const _ExploreCta({required this.available, required this.onTap});

  /// How many paths there actually are. The copy used to say "Ten", which was
  /// true only until somebody added an eleventh or retired one.
  final int available;

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
            style: TackText.sectionHeader.copyWith(color: TackColors.onBrand),
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            available == 0
                ? 'Real jobs, what they pay in Bangladesh, and what it takes to '
                      'get one. Nothing to commit to.'
                : '$available career paths, what they involve, and how to try '
                      'them. Nothing to commit to.',
            style: TackText.bodyMuted.copyWith(color: const Color(0xD1FFFFFF)),
          ),
          const SizedBox(height: TackSpace.lg),
          TackButton.amber('Have a look', onPressed: onTap),
        ],
      ),
    );
  }
}

/// The maroon date card, final year and after only.
///
/// Overdue rows sit above the rest and are counted in the heading, because a
/// missed date buried in a list of upcoming ones gets missed a second time.
class _NextSevenDays extends StatelessWidget {
  const _NextSevenDays({
    required this.entries,
    required this.overdue,
    required this.today,
    required this.hasApplications,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<TimelineEntry> entries;
  final List<TimelineEntry> overdue;
  final bool hasApplications;
  final DateTime today;
  final void Function(TimelineEntry entry) onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final rows = [...overdue, ...entries].take(4).toList();
    const onMaroon = Color(0xD1FFFFFF);

    return TackCard(
      background: TackColors.maroon,
      onTap: onSeeAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Next seven days',
                  style: TackText.cardTitle.copyWith(color: TackColors.onBrand),
                ),
              ),
              if (overdue.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: TackColors.amber,
                    borderRadius: TackRadius.pillAll,
                  ),
                  child: Text(
                    '${overdue.length} late',
                    style: TackText.pill.copyWith(color: TackColors.onAccent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          if (rows.isEmpty)
            Text(
              // "Add two more" told a student with no applications at all that
              // they had some already. What is empty here is the *dates*, and
              // whether they have applied is a different question.
              hasApplications
                  ? 'Nothing due this week. A good week to line up what is next.'
                  : 'Nothing here yet. Add an application and its dates show up here.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                height: 1.45,
                color: onMaroon,
              ),
            )
          else
            for (final entry in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: TackSpace.sm),
                child: GestureDetector(
                  onTap: () => onOpen(entry),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 30),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 82,
                          child: Text(
                            entry.relativeTo(today),
                            style: TackText.pill.copyWith(
                              color: entry.isOverdue
                                  ? TackColors.warnOnBrand
                                  : TackColors.onBrand,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TackText.body.copyWith(
                              color: TackColors.onBrand,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RoadmapProgressCard extends StatelessWidget {
  const _RoadmapProgressCard({required this.roadmap, required this.onTap});

  final RoadmapSummary roadmap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Your roadmap', style: TackText.cardTitle)),
              TackCountUp(
                roadmap.percent,
                suffix: '%',
                style: TackText.cardTitle.copyWith(
                  color: TackColors.maroonText,
                ),
                semanticsLabel: '${roadmap.percent} percent of your roadmap',
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          TackProgressBar(value: roadmap.fraction, height: 8),
          const SizedBox(height: TackSpace.sm),
          Row(
            children: [
              Text(
                '${roadmap.done} of ${roadmap.total} steps done',
                style: TackText.meta,
              ),
              if (roadmap.activeMilestone case final milestone?) ...[
                // Two counts running straight into each other read as one
                // broken sentence — "8 of 23 steps done Build with a fram…".
                Text('  ·  ', style: TackText.meta),
                Flexible(
                  child: Text(
                    milestone,
                    style: TackText.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The floating coach button.
///
/// Labelled, not a bare icon. A lone speech bubble in the corner of a careers
/// app could be help, feedback, or a chatbot nobody wants; "Ask" says what
/// happens when you press it, and it still fits beside the bottom bar at
/// 360px.
class _CoachButton extends StatelessWidget {
  const _CoachButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask your coach',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: TackColors.maroon,
            borderRadius: BorderRadius.all(TackRadius.buttonRound),
            boxShadow: TackShadow.fab,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TackIcon(TackIcons.coach, size: 21, color: TackColors.onBrand),
              const SizedBox(width: TackSpace.sm),
              Text('Ask', style: TackText.button.copyWith(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav();

  @override
  Widget build(BuildContext context) => const TackTabBar(current: Routes.home);
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const TackScaffold(
      header: TackHomeHeader(initials: '–'),
      bottomNav: _Nav(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackSkeleton(width: 140, height: 28, radius: 14),
          SizedBox(height: TackSpace.lg),
          TackSkeleton(height: 128, radius: 20),
          SizedBox(height: TackSpace.stackLoose),
          TackSkeleton(height: 176, radius: 20),
          SizedBox(height: TackSpace.stackLoose),
          TackSkeleton(height: 190, radius: 20),
        ],
      ),
    );
  }
}

/// The two tools that had no way in.
///
/// Deliberately last on the dashboard and deliberately quiet: neither is
/// something a student does daily, and both are what you reach for when an
/// interview is actually coming. Putting them above the roadmap would suggest
/// otherwise.
class _GetReady extends StatelessWidget {
  const _GetReady({required this.onInterview, required this.onAnalyse});

  final VoidCallback onInterview;
  final VoidCallback onAnalyse;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('When it gets real', style: TackText.sectionHeader),
      const SizedBox(height: TackSpace.md),
      TackCard(
        child: Column(
          children: [
            _Tool(
              icon: TackIcons.practice,
              title: 'Practise an interview',
              body: 'Real questions for your role. Free — no daily limit.',
              onTap: onInterview,
            ),
            const TackDivider(),
            _Tool(
              icon: TackIcons.file,
              title: 'Check a job description',
              body: 'Paste one in and see what you already match.',
              onTap: onAnalyse,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TackTapRow(
    onTap: onTap,
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: TackSpace.md),
          child: TackIcon(icon, size: 21, color: TackColors.maroonText),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TackText.rowTitle),
              const SizedBox(height: 2),
              Text(body, style: TackText.meta),
            ],
          ),
        ),
        TackIcon(TackIcons.chevronRight, size: 18, color: TackColors.muted),
      ],
    ),
  );
}
