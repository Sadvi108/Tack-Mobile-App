import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/roadmap_models.dart';

/// The tint pair for each task type. Colour is never the only signal — the tag
/// carries its label too.
({Color background, Color foreground}) taskTypeTint(TaskType type) =>
    switch (type) {
      TaskType.skill => (
        background: TackColors.tealTint,
        foreground: TackColors.tealText,
      ),
      TaskType.project => (
        background: TackColors.maroonTint,
        foreground: TackColors.maroon,
      ),
      TaskType.certificate => (
        background: TackColors.amberTint,
        foreground: TackColors.amberText,
      ),
      TaskType.networking => (
        background: TackColors.blueTint,
        foreground: TackColors.blueText,
      ),
      TaskType.application => (
        background: TackColors.line,
        foreground: TackColors.muted,
      ),
      TaskType.cv => (
        background: TackColors.tealDeepTint,
        foreground: TackColors.tealText,
      ),
    };

/// One roadmap task.
///
/// Ticking it strikes the title and greys it. The point gain is announced by
/// the caller as a toast, and the score itself is recomputed on the server.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    this.onLongPress,
    this.enabled = true,
  });

  final RoadmapTask task;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tint = taskTypeTint(task.type);
    final titleColour = task.isDone ? TackColors.muted : TackColors.ink;

    return Semantics(
      checked: task.isDone,
      label: task.title,
      child: GestureDetector(
        onTap: enabled ? onToggle : null,
        onLongPress: enabled ? onLongPress : null,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: TackMotion.fast,
                  margin: const EdgeInsets.only(top: 1),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: task.isDone ? TackColors.maroon : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: task.isDone
                          ? TackColors.maroon
                          : TackColors.strokeFaint,
                      width: 1.5,
                    ),
                  ),
                  child: task.isDone
                      ? const TackIcon(
                          TackIcons.check,
                          size: 15,
                          color: TackColors.white,
                          strokeWidth: 3,
                        )
                      : null,
                ),
                const SizedBox(width: TackSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TackText.rowTitle.copyWith(
                          color: titleColour,
                          decoration: task.isDone
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: TackColors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TackPill(
                            task.type.label,
                            background: tint.background,
                            foreground: tint.foreground,
                          ),
                          if (task.dueDate != null)
                            TackPill(
                              _dueLabel(task),
                              background: task.isOverdue
                                  ? TackColors.maroonTint
                                  : TackColors.line,
                              foreground: task.isOverdue
                                  ? TackColors.danger
                                  : TackColors.muted,
                            ),
                          if (task.isShared)
                            const TackPill(
                              'Counts twice',
                              background: TackColors.amberTint,
                              foreground: TackColors.amberText,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TackSpace.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+${task.points}',
                    style: TackText.pill.copyWith(
                      color: task.isDone ? TackColors.muted : TackColors.maroon,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _dueLabel(RoadmapTask task) {
    final due = task.dueDate!;
    final now = DateTime.now();
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return switch (days) {
      < 0 => 'Overdue',
      0 => 'Due today',
      1 => 'Due tomorrow',
      < 14 => 'Due in $days days',
      _ => 'Due ${due.day}/${due.month}',
    };
  }
}
