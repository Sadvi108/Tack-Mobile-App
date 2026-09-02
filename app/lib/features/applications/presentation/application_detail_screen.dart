import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../score/data/score_repository.dart';
import '../data/application_models.dart';
import '../data/application_repository.dart';
import '../data/status_machine.dart';

final _detailProvider = FutureProvider.family<JobApplication?, String>((
  ref,
  id,
) async {
  final all = await ref.watch(applicationsProvider(null).future);
  return all.where((a) => a.id == id).firstOrNull;
});

final _historyProvider = FutureProvider.family<List<StatusChange>, String>(
  (ref, id) => ref.watch(applicationRepositoryProvider).history(id),
);

/// One application in full, with the timeline of every status change.
///
/// The timeline is written by a database trigger, so it is a record of what
/// actually happened rather than something the client can rewrite.
class ApplicationDetailScreen extends ConsumerWidget {
  const ApplicationDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationAsync = ref.watch(_detailProvider(id));
    final history =
        ref.watch(_historyProvider(id)).value ?? const <StatusChange>[];

    return applicationAsync.when(
      loading: () => TackScaffold(
        header: TackHeader(title: 'Application', onBack: () => context.pop()),
        body: const TackSkeleton(height: 260, radius: 20),
      ),
      error: (_, _) => TackScaffold(
        header: TackHeader(title: 'Application', onBack: () => context.pop()),
        body: TackErrorState(
          body:
              'This application did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(_detailProvider(id)),
        ),
      ),
      data: (application) {
        if (application == null) {
          return TackScaffold(
            header: TackHeader(
              title: 'Application',
              onBack: () => context.pop(),
            ),
            body: const TackErrorState(
              title: 'That application is gone',
              body: 'It may have been deleted. Go back to the list.',
            ),
          );
        }

        final primaryMove = StatusMachine.primaryMove(application.status);

        return TackScaffold(
          header: TackHeader(
            title: application.title,
            onBack: () => context.pop(),
            trailing: GestureDetector(
              onTap: () => _showMenu(context, ref, application),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: TackSpace.tapTarget,
                height: TackSpace.tapTarget,
                child: Center(
                  child: TackIcon(
                    TackIcons.more,
                    size: 22,
                    color: TackColors.ink,
                  ),
                ),
              ),
            ),
          ),
          pinnedCta: primaryMove == null
              ? TackButton.secondary(
                  'Change status',
                  onPressed: () => _changeStatus(context, ref, application),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TackButton(
                      StatusMachine.moveLabel(primaryMove),
                      onPressed: () =>
                          _move(context, ref, application, primaryMove),
                    ),
                    const SizedBox(height: TackSpace.sm),
                    TackButton.ghost(
                      'Something else happened',
                      onPressed: () => _changeStatus(context, ref, application),
                    ),
                  ],
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            application.companyName ?? 'Unknown company',
                            style: TackText.cardTitle,
                          ),
                        ),
                        StatusPill(application.status),
                      ],
                    ),
                    if (application.location != null) ...[
                      const SizedBox(height: TackSpace.xs),
                      Text(application.location!, style: TackText.meta),
                    ],
                    if (application.appliedAt != null) ...[
                      const SizedBox(height: TackSpace.sm),
                      Text(
                        'Applied on ${_date(application.appliedAt!)}',
                        style: TackText.meta,
                      ),
                    ],
                    if (application.sourceUrl != null) ...[
                      const SizedBox(height: TackSpace.md),
                      TackButton.ghost(
                        'Open the listing',
                        fullWidth: false,
                        icon: TackIcon(
                          TackIcons.externalLink,
                          size: 17,
                          color: TackColors.maroonText,
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(application.sourceUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              _NextActionCard(
                application: application,
                onEdit: () => _editNext(context, ref, application),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              Text('What has happened', style: TackText.sectionHeader),
              const SizedBox(height: TackSpace.md),
              TackCard(
                child: history.isEmpty
                    ? Text('Nothing recorded yet.', style: TackText.bodyMuted)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < history.length; i++)
                            _TimelineRow(
                              change: history[i],
                              isFirst: i == 0,
                              isLast: i == history.length - 1,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              _NotesCard(
                application: application,
                onEdit: () => _editNotes(context, ref, application),
              ),
              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(applicationsProvider(null))
      ..invalidate(applicationCountsProvider)
      ..invalidate(upcomingApplicationsProvider)
      ..invalidate(_historyProvider(id))
      ..invalidate(readinessProvider);
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    JobApplication application,
    TackStatus to,
  ) async {
    try {
      await ref
          .read(applicationRepositoryProvider)
          .setStatus(application.id, to);
      _refresh(ref);
      if (context.mounted) {
        TackToast.show(context, message: 'Moved to ${to.label.toLowerCase()}.');
      }
    } catch (e) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: Failure.from(e).message,
          kind: TackToastKind.error,
        );
      }
    }
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    JobApplication application,
  ) async {
    // Only legal moves are offered. The database would refuse anything else,
    // and a button that fails on tap is worse than no button.
    final moves = StatusMachine.movesFrom(application.status);
    final picked = await showTackSheet<TackStatus>(
      context: context,
      title: 'What happened?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final move in moves)
            TackTapRow(
              onTap: () => Navigator.of(context).pop(move),
              padding: const EdgeInsets.symmetric(
                horizontal: TackSpace.screen,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      StatusMachine.moveLabel(move),
                      style: TackText.rowTitle,
                    ),
                  ),
                  StatusPill(move),
                ],
              ),
            ),
          const SizedBox(height: TackSpace.lg),
        ],
      ),
    );
    if (picked != null && context.mounted) {
      await _move(context, ref, application, picked);
    }
  }

  Future<void> _editNext(
    BuildContext context,
    WidgetRef ref,
    JobApplication application,
  ) async {
    final controller = TextEditingController(
      text: application.nextAction ?? '',
    );
    DateTime? date = application.nextActionDate;

    final saved = await showTackSheet<bool>(
      context: context,
      title: 'What is next?',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            TackSpace.screen,
            0,
            TackSpace.screen,
            MediaQuery.viewInsetsOf(sheetContext).bottom + TackSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TackTextField(
                label: 'The next thing to do',
                hint: 'Follow up with the recruiter',
                controller: controller,
                autofocus: true,
              ),
              const SizedBox(height: TackSpace.stack),
              TackSelectField<DateTime>(
                label: 'When',
                hint: 'Pick a date',
                value: date,
                valueLabel: _date,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: date ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 30),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
              ),
              const SizedBox(height: TackSpace.xl),
              TackButton(
                'Save',
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    final text = controller.text.trim();
    controller.dispose();
    if (saved != true) return;

    await ref.read(applicationRepositoryProvider).update(application.id, {
      'next_action': text.isEmpty ? null : text,
      'next_action_date': date?.toIso8601String().substring(0, 10),
    });
    _refresh(ref);
  }

  Future<void> _editNotes(
    BuildContext context,
    WidgetRef ref,
    JobApplication application,
  ) async {
    final controller = TextEditingController(text: application.notes ?? '');
    final saved = await showTackSheet<bool>(
      context: context,
      title: 'Your notes',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TackTextField(
              hint:
                  'Who you spoke to, what they asked, anything worth remembering',
              controller: controller,
              maxLines: 6,
              autofocus: true,
            ),
            const SizedBox(height: TackSpace.lg),
            Builder(
              builder: (sheetContext) => TackButton(
                'Save',
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ),
          ],
        ),
      ),
    );

    final text = controller.text.trim();
    controller.dispose();
    if (saved != true) return;

    await ref.read(applicationRepositoryProvider).update(application.id, {
      'notes': text.isEmpty ? null : text,
    });
    _refresh(ref);
  }

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    JobApplication application,
  ) async {
    final action = await showTackSheet<String>(
      context: context,
      title: application.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TackTapRow(
            onTap: () => Navigator.of(context).pop('delete'),
            padding: const EdgeInsets.symmetric(
              horizontal: TackSpace.screen,
              vertical: 14,
            ),
            child: Row(
              children: [
                TackIcon(
                  TackIcons.trash,
                  size: 20,
                  color: TackColors.dangerText,
                ),
                const SizedBox(width: TackSpace.md),
                Text(
                  'Remove this application',
                  style: TackText.rowTitle.copyWith(
                    color: TackColors.dangerText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.lg),
        ],
      ),
    );

    if (action != 'delete' || !context.mounted) return;

    final confirmed = await confirmTackAction(
      context,
      title: 'Remove this application?',
      body: 'It disappears from your tracker. Nothing is sent to the employer.',
      confirmLabel: 'Remove it',
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(applicationRepositoryProvider).remove(application.id);
    _refresh(ref);
    if (context.mounted) {
      context.pop();
      TackToast.show(context, message: 'Removed.');
    }
  }

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.application, required this.onEdit});

  final JobApplication application;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final has =
        application.nextAction != null || application.nextActionDate != null;
    return TackCard(
      emphasised: has,
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Next step', style: TackText.cardTitle),
          const SizedBox(height: TackSpace.sm),
          Text(
            has
                ? application.nextAction ?? 'Follow up'
                : 'Nothing set. Add one so it does not slip.',
            style: has ? TackText.body : TackText.bodyMuted,
          ),
          if (application.nextActionDate != null) ...[
            const SizedBox(height: TackSpace.sm),
            TackPill(
              ApplicationDetailScreen._date(application.nextActionDate!),
              background: (application.daysUntilNextAction ?? 1) < 0
                  ? TackColors.maroonTint
                  : TackColors.amberTint,
              foreground: (application.daysUntilNextAction ?? 1) < 0
                  ? TackColors.dangerText
                  : TackColors.amberText,
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.application, required this.onEdit});

  final JobApplication application;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Notes', style: TackText.cardTitle)),
              TackIcon(TackIcons.edit, size: 18, color: TackColors.muted),
            ],
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            application.notes?.isNotEmpty == true
                ? application.notes!
                : 'Nothing written down yet.',
            style: application.notes?.isNotEmpty == true
                ? TackText.body
                : TackText.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.change,
    required this.isFirst,
    required this.isLast,
  });

  final StatusChange change;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: isLast ? TackColors.maroonText : TackColors.line2,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: SizedBox(
                    width: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: TackColors.line),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : TackSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFirst && change.fromStatus == null
                        ? 'Added as ${change.toStatus.label.toLowerCase()}'
                        : 'Moved to ${change.toStatus.label.toLowerCase()}',
                    style: TackText.rowTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ApplicationDetailScreen._date(change.changedAt),
                    style: TackText.monoLabelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
