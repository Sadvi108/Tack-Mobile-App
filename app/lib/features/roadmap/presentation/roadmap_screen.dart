import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:convert';

import '../../../core/failure.dart';
import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/profile_repository.dart';
import '../../score/data/score_repository.dart';
import '../data/roadmap_models.dart';
import '../data/roadmap_repository.dart';
import 'task_tile.dart';

/// The roadmap.
///
/// Milestones in order, locked ones stating what unlocks them rather than
/// showing a padlock alone — the sequence has to read as a route, not a
/// paywall. The state machine lives in the database; this screen reflects it
/// and refetches after every change rather than guessing.
class RoadmapScreen extends ConsumerStatefulWidget {
  const RoadmapScreen({super.key});

  @override
  ConsumerState<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends ConsumerState<RoadmapScreen> {
  int _selected = 0;
  final _expanded = <String>{};

  Future<void> _toggle(RoadmapTask task) async {
    final done = !task.isDone;

    try {
      await ref
          .read(roadmapRepositoryProvider)
          .setTaskDone(task.id, done: done);
      ref
        ..invalidate(roadmapsProvider)
        ..invalidate(readinessProvider)
        ..invalidate(weekChangeProvider);
      if (!mounted) return;
      if (done) {
        TackToast.show(context, message: 'Done. +${task.points} points.');
      }
    } catch (e) {
      final failure = Failure.from(e);
      if (!mounted) return;

      // Ticking a task is the change students make most often, and the one
      // most likely to happen with no signal. Queue it instead of losing it.
      if (failure.isOffline) {
        await ref
            .read(localDbProvider)
            .enqueue(
              kind: 'task_done',
              targetId: task.id,
              payload: jsonEncode({'is_done': done}),
            );
        if (!mounted) return;
        TackToast.show(
          context,
          message:
              'Saved on this phone. It will sync when you are back online.',
          kind: TackToastKind.info,
        );
        return;
      }

      TackToast.show(
        context,
        message: failure.message,
        kind: TackToastKind.error,
      );
    }
  }

  Future<void> _addTask(String milestoneId) async {
    final controller = TextEditingController();
    final title = await showTackSheet<String>(
      context: context,
      title: 'Add your own step',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Something you want to do that is not already on the list.',
              style: TackText.bodyMuted,
            ),
            const SizedBox(height: TackSpace.lg),
            TackTextField(
              hint: 'For example, finish the CS50 problem set',
              controller: controller,
              autofocus: true,
            ),
            const SizedBox(height: TackSpace.lg),
            Builder(
              builder: (sheetContext) => TackButton(
                'Add it',
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (title == null || title.isEmpty || !mounted) return;
    await ref
        .read(roadmapRepositoryProvider)
        .addCustomTask(milestoneId: milestoneId, title: title);
    ref.invalidate(roadmapsProvider);
    if (mounted) TackToast.show(context, message: 'Added to your roadmap.');
  }

  @override
  Widget build(BuildContext context) {
    final roadmapsAsync = ref.watch(roadmapsProvider);
    final mode = ref.watch(modeProvider);
    final tabs = TackTabs.forMode(mode.name);

    return TackScaffold(
      bottomNav: TackBottomNav(
        tabs: tabs,
        currentIndex: tabs.indexWhere((t) => t.route == Routes.roadmap),
        onTap: (i) => context.go(tabs[i].route),
      ),
      header: const TackHeader(title: 'Your roadmap'),
      body: roadmapsAsync.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TackSkeleton(height: 72, radius: 20),
            SizedBox(height: TackSpace.stack),
            TackSkeleton(height: 210, radius: 20),
          ],
        ),
        error: (_, _) => TackErrorState(
          body:
              'Your roadmap did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(roadmapsProvider),
        ),
        data: (roadmaps) {
          if (roadmaps.isEmpty) {
            return TackEmptyState(
              title: 'No roadmap yet',
              body:
                  'Pick a career path and Tack turns it into a route you can '
                  'actually follow, one step at a time.',
              primaryLabel: 'Explore career paths',
              onPrimary: () => context.go(Routes.paths),
            );
          }

          final index = _selected.clamp(0, roadmaps.length - 1);
          final roadmap = roadmaps[index];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Two paths at once get a switcher. One path gets no chrome it
              // does not need.
              if (roadmaps.length > 1) ...[
                Row(
                  children: [
                    for (var i = 0; i < roadmaps.length; i++) ...[
                      if (i > 0) const SizedBox(width: TackSpace.sm),
                      Expanded(
                        child: CountFilterChip(
                          label: roadmaps[i].title,
                          count: roadmaps[i].doneCount,
                          selected: i == index,
                          onTap: () => setState(() => _selected = i),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: TackSpace.stack),
              ],

              TackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(roadmap.title, style: TackText.cardTitle),
                        ),
                        Text(
                          '${(roadmap.progress * 100).round()}%',
                          style: TackText.cardTitle.copyWith(
                            color: TackColors.maroon,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TackSpace.md),
                    TackProgressBar(value: roadmap.progress, height: 8),
                    const SizedBox(height: TackSpace.sm),
                    Text(
                      '${roadmap.doneCount} of ${roadmap.totalCount} steps done',
                      style: TackText.meta,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              for (final milestone in roadmap.milestones) ...[
                _MilestoneCard(
                  milestone: milestone,
                  expanded:
                      _expanded.contains(milestone.id) ||
                      (milestone.state == MilestoneState.active &&
                          !_expanded.contains('collapsed:${milestone.id}')),
                  onToggleExpanded: () => setState(() {
                    if (milestone.state == MilestoneState.active) {
                      final key = 'collapsed:${milestone.id}';
                      _expanded.contains(key)
                          ? _expanded.remove(key)
                          : _expanded.add(key);
                    } else {
                      _expanded.contains(milestone.id)
                          ? _expanded.remove(milestone.id)
                          : _expanded.add(milestone.id);
                    }
                  }),
                  onToggleTask: _toggle,
                  onAddTask: () => _addTask(milestone.id),
                ),
                const SizedBox(height: TackSpace.stack),
              ],

              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleTask,
    required this.onAddTask,
  });

  final RoadmapMilestone milestone;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(RoadmapTask task) onToggleTask;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final locked = milestone.state == MilestoneState.locked;
    final completed = milestone.state == MilestoneState.completed;

    return TackCard(
      emphasised: milestone.state == MilestoneState.active,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StateDot(state: milestone.state),
                const SizedBox(width: TackSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone.title,
                        style: TackText.cardTitle.copyWith(
                          color: locked ? TackColors.muted : TackColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            completed
                                ? 'Done'
                                : '${milestone.doneCount} of ${milestone.totalCount} steps',
                            style: TackText.meta.copyWith(fontSize: 13.5),
                          ),
                          if (milestone.typicalSemester != null) ...[
                            Text(
                              ' · ',
                              style: TackText.meta.copyWith(fontSize: 13.5),
                            ),
                            Text(
                              'around semester ${milestone.typicalSemester}',
                              style: TackText.meta.copyWith(fontSize: 13.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                TackIcon(
                  expanded ? TackIcons.chevronUp : TackIcons.chevronDown,
                  size: 20,
                  color: TackColors.muted,
                ),
              ],
            ),
          ),

          // A locked milestone always says what opens it. Showing only a
          // padlock makes a route look like a paywall.
          if (locked && milestone.unlockText != null) ...[
            const SizedBox(height: TackSpace.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: TackColors.sailWhite,
                borderRadius: TackRadius.inputAll,
              ),
              child: Text(
                'Opens when you: ${milestone.unlockText}',
                style: TackText.meta.copyWith(fontSize: 13.5),
              ),
            ),
          ],

          if (expanded) ...[
            if (milestone.description != null) ...[
              const SizedBox(height: TackSpace.md),
              Text(milestone.description!, style: TackText.bodyMuted),
            ],
            const SizedBox(height: TackSpace.sm),
            for (final task in milestone.tasks) ...[
              const TackDivider(),
              TaskTile(
                task: task,
                enabled: !locked,
                onToggle: () => onToggleTask(task),
              ),
            ],
            if (!locked) ...[
              const TackDivider(),
              const SizedBox(height: TackSpace.sm),
              TackButton.ghost(
                '+ Add your own step',
                onPressed: onAddTask,
                fullWidth: false,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});

  final MilestoneState state;

  @override
  Widget build(BuildContext context) {
    final (colour, filled) = switch (state) {
      MilestoneState.completed => (TackColors.teal, true),
      MilestoneState.active => (TackColors.maroon, true),
      MilestoneState.locked => (TackColors.line2, false),
    };

    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: filled ? colour : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: 1.5),
      ),
      child: state == MilestoneState.completed
          ? const TackIcon(
              TackIcons.check,
              size: 14,
              color: TackColors.white,
              strokeWidth: 3,
            )
          : null,
    );
  }
}
