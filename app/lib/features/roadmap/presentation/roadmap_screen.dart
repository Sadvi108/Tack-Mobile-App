import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:convert';

import '../../../core/failure.dart';
import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../dashboard/presentation/motion.dart';
import '../../score/data/score_repository.dart';
import '../data/roadmap_models.dart';
import '../data/roadmap_repository.dart';
import 'journey_line.dart';
import 'task_tile.dart';
import '../../../routing/tab_bar.dart';

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

  /// Long-pressing a step. Until now `setTaskDue` and `deleteTask` existed in
  /// the repository and nothing could reach them — `onLongPress` was never
  /// passed to the tile — so a student could neither move a date nor remove a
  /// step they were never going to do.
  Future<void> _editTask(RoadmapTask task) async {
    final action = await showTackSheet<String>(
      context: context,
      title: task.title,
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
            Builder(
              builder: (sheetContext) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TackButton.secondary(
                    task.dueDate == null ? 'Give it a date' : 'Move the date',
                    onPressed: () => Navigator.of(sheetContext).pop('due'),
                  ),
                  const SizedBox(height: TackSpace.stack),
                  TackButton.ghost(
                    'Remove this step',
                    onPressed: () => Navigator.of(sheetContext).pop('delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final repository = ref.read(roadmapRepositoryProvider);

    if (action == 'due') {
      final picked = await showDatePicker(
        context: context,
        initialDate: task.dueDate ?? DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );
      if (picked == null || !mounted) return;
      await repository.setTaskDue(task.id, picked);
      ref.invalidate(roadmapsProvider);
      if (mounted) TackToast.show(context, message: 'Date moved.');
      return;
    }

    // Removing a step changes the score, because roadmap_progress is a
    // fraction of the steps that exist. Worth confirming.
    final sure = await confirmTackAction(
      context,
      title: 'Remove this step?',
      body:
          'It comes off your roadmap and stops counting toward your readiness '
          'score. You can add your own step back later.',
      confirmLabel: 'Remove it',
    );
    if (!sure || !mounted) return;
    await repository.deleteTask(task.id);
    ref
      ..invalidate(roadmapsProvider)
      ..invalidate(readinessProvider);
    if (mounted) TackToast.show(context, message: 'Removed.');
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
    return TackScaffold(
      bottomNav: const TackTabBar(current: Routes.roadmap),
      header: const TackHeader(title: 'Your roadmap'),
      // The body brings its own ListView so the milestones build lazily; the
      // whole roadmap used to be an eager Column inside the shell's scroll
      // view, so every task of every milestone was laid out on every frame.
      scrollable: false,
      padBody: false,
      body: roadmapsAsync.when(
        // Each of these is a ListView rather than a bare child. The shell no
        // longer wraps the body in a scroll view, so anything handed to it
        // directly is stretched to the full height — which turned the empty
        // state into a white card running the length of the screen.
        loading: () => ListView(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
          children: const [
            TackSkeleton(height: 108, radius: 20),
            SizedBox(height: TackSpace.stackLoose),
            TackSkeleton(height: 140, radius: 20),
            SizedBox(height: TackSpace.stack),
            TackSkeleton(height: 96, radius: 20),
          ],
        ),
        error: (_, _) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
          children: [
            TackErrorState(
              body:
                  'Your roadmap did not load. Check your connection and try again.',
              onRetry: () => ref.invalidate(roadmapsProvider),
            ),
          ],
        ),
        data: (roadmaps) {
          if (roadmaps.isEmpty) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
              children: [
                TackEmptyState(
                  title: 'No roadmap yet',
                  body:
                      'Pick a career path and Tack turns it into a route you '
                      'can actually follow, one step at a time.',
                  primaryLabel: 'Explore career paths',
                  onPrimary: () => context.push(Routes.paths),
                ),
              ],
            );
          }

          final index = _selected.clamp(0, roadmaps.length - 1);
          final roadmap = roadmaps[index];
          final milestones = roadmap.milestones;
          var step = 0;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
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

              TackReveal(
                index: step++,
                child: _RoadmapSummary(roadmap: roadmap),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              // The journey. Each milestone sits beside its own segment of the
              // spine, and the spine takes the card's height from the
              // IntrinsicHeight row rather than being told what it is.
              for (var i = 0; i < milestones.length; i++)
                TackReveal(
                  index: step++,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JourneyLine(
                          state: milestones[i].state,
                          isFirst: i == 0,
                          isLast: i == milestones.length - 1,
                          progress: milestones[i].progress,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: TackSpace.stack,
                            ),
                            child: _MilestoneCard(
                              milestone: milestones[i],
                              expanded:
                                  _expanded.contains(milestones[i].id) ||
                                  (milestones[i].state ==
                                          MilestoneState.active &&
                                      !_expanded.contains(
                                        'collapsed:${milestones[i].id}',
                                      )),
                              onToggleExpanded: () => setState(() {
                                final m = milestones[i];
                                if (m.state == MilestoneState.active) {
                                  final key = 'collapsed:${m.id}';
                                  _expanded.contains(key)
                                      ? _expanded.remove(key)
                                      : _expanded.add(key);
                                } else {
                                  _expanded.contains(m.id)
                                      ? _expanded.remove(m.id)
                                      : _expanded.add(m.id);
                                }
                              }),
                              onToggleTask: _toggle,
                              onEditTask: _editTask,
                              onAddTask: () => _addTask(milestones[i].id),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }
}

/// The figure at the top, and one sentence saying what it means.
///
/// A percentage on its own is a verdict. "23 steps left, about two a week
/// before you graduate" is something a student can act on — and when the pace
/// is impossible it says so rather than quietly dropping steps to make the
/// number look achievable.
class _RoadmapSummary extends StatelessWidget {
  const _RoadmapSummary({required this.roadmap});

  final Roadmap roadmap;

  @override
  Widget build(BuildContext context) {
    final percent = (roadmap.progress * 100).round();
    final pace = roadmap.pacePerWeek(DateTime.now());

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR ROUTE', style: TackText.monoLabelSmall),
          const SizedBox(height: TackSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  roadmap.title,
                  style: TackText.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              TackCountUp(
                percent,
                suffix: '%',
                style: TackText.cardTitle.copyWith(color: TackColors.maroon),
                semanticsLabel: '$percent percent of your roadmap done',
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          TackProgressBar(value: roadmap.progress, height: 8),
          const SizedBox(height: TackSpace.sm),
          Text(_sentence(pace), style: TackText.meta),
          if (roadmap.skippedCount > 0) ...[
            const SizedBox(height: TackSpace.sm),
            Text(
              roadmap.skippedCount == 1
                  ? 'One step was left out because you already have that skill.'
                  : '${roadmap.skippedCount} steps were left out because you '
                        'already have those skills.',
              style: TackText.meta.copyWith(color: TackColors.tealText),
            ),
          ],
        ],
      ),
    );
  }

  String _sentence(double? pace) {
    final left = roadmap.totalCount - roadmap.doneCount;
    if (roadmap.totalCount == 0) return 'This route has no steps on it yet.';
    if (left == 0) return 'Every step done. That is the whole route.';

    final base = '${roadmap.doneCount} of ${roadmap.totalCount} steps done';
    if (pace == null) return '$base · $left to go';

    // Rounded to a half so it reads as a rhythm rather than a measurement.
    final weekly = (pace * 2).round() / 2;
    if (weekly <= 1) return '$base · about one a week from here';
    if (weekly > 6) {
      // Said plainly rather than hidden. The alternative was quietly deleting
      // steps until the arithmetic looked comfortable.
      return '$base · that is $left steps in the time left, which is a lot. '
          'Move a date, or start with the ones worth the most.';
    }
    return '$base · about ${weekly.toStringAsFixed(weekly % 1 == 0 ? 0 : 1)} '
        'a week from here';
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleTask,
    required this.onEditTask,
    required this.onAddTask,
  });

  final RoadmapMilestone milestone;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(RoadmapTask task) onToggleTask;
  final Future<void> Function(RoadmapTask task) onEditTask;
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
                // No state dot here any more: the node on the spine to the
                // left carries the state, and two markers for one fact read
                // as two different facts.
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
                onLongPress: locked ? null : () => onEditTask(task),
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
