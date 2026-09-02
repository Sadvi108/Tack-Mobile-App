import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../data/application_models.dart';
import '../data/application_repository.dart';
import 'add_application_sheet.dart';
import '../../../routing/tab_bar.dart';

/// The application tracker, as its own screen.
///
/// Radar is where a student normally reaches this — tracking is the second
/// half of finding a job, so it lives in the same destination. This screen
/// stays because `/applications` is still a real route: notifications point at
/// it, the readiness breakdown points at it, and a deep link into a single
/// application has to land somewhere.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TackScaffold(
      bottomNav: const TackTabBar(current: Routes.radar),
      header: const TackHeader(title: 'Applications'),
      body: const ApplicationsBody(),
    );
  }
}

/// The list itself, without a scaffold, so Radar can host it under its own
/// header and segmented control.
class ApplicationsBody extends ConsumerStatefulWidget {
  const ApplicationsBody({super.key});

  @override
  ConsumerState<ApplicationsBody> createState() => _ApplicationsBodyState();
}

class _ApplicationsBodyState extends ConsumerState<ApplicationsBody> {
  TackStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final counts =
        ref.watch(applicationCountsProvider).value ?? ApplicationCounts.empty;
    final listAsync = ref.watch(applicationsProvider(_filter));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              CountFilterChip(
                label: 'All',
                count: counts.total,
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final status in TackStatus.values) ...[
                const SizedBox(width: TackSpace.sm),
                CountFilterChip(
                  label: status.label,
                  count: counts[status],
                  selected: _filter == status,
                  onTap: () => setState(() => _filter = status),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TackSpace.lg),
        listAsync.when(
          loading: () => const Column(
            children: [
              TackSkeleton(height: 110, radius: 18),
              SizedBox(height: TackSpace.stack),
              TackSkeleton(height: 110, radius: 18),
            ],
          ),
          error: (_, _) => TackErrorState(
            body:
                'Your applications did not load. Check your connection and try again.',
            onRetry: () => ref.invalidate(applicationsProvider(_filter)),
          ),
          data: (applications) {
            if (applications.isEmpty) {
              return TackEmptyState(
                title: _filter == null
                    ? 'No applications yet'
                    : 'Nothing at ${_filter!.label.toLowerCase()}',
                body: _filter == null
                    ? 'Track every job you apply to in one place. You will start to see '
                          'what is working and what is not.'
                    : 'Applications you move to this stage will show up here.',
                primaryLabel: _filter == null
                    ? 'Add your first application'
                    : null,
                onPrimary: _filter == null ? () => _add(context) : null,
              );
            }

            return Column(
              children: [
                for (final application in applications) ...[
                  _ApplicationCard(
                    application: application,
                    onTap: () =>
                        context.push(Routes.application(application.id)),
                  ),
                  const SizedBox(height: TackSpace.stack),
                ],
                const SizedBox(height: 90),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final created = await showAddApplicationSheet(context, ref);
    if (created && context.mounted) {
      ref
        ..invalidate(applicationCountsProvider)
        ..invalidate(applicationsProvider(_filter));
    }
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.onTap});

  final JobApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = application.daysUntilNextAction;

    return TackCard(
      compact: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The card leads with what has to happen next, not with the job
          // title — the title is not the thing a student needs to act on.
          if (application.nextAction != null || days != null) ...[
            Row(
              children: [
                TackIcon(
                  TackIcons.calendar,
                  size: 15,
                  color: (days ?? 1) < 0
                      ? TackColors.dangerText
                      : TackColors.maroonText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _nextLine(application),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TackText.pill.copyWith(
                      color: (days ?? 1) < 0
                          ? TackColors.dangerText
                          : TackColors.maroonText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TackSpace.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.title,
                      style: TackText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (application.companyName != null)
                          application.companyName!,
                        if (application.location != null) application.location!,
                      ].join(' · '),
                      style: TackText.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              StatusPill(application.status),
            ],
          ),
        ],
      ),
    );
  }

  static String _nextLine(JobApplication application) {
    final days = application.daysUntilNextAction;
    final what = application.nextAction ?? 'Follow up';
    final when = switch (days) {
      null => null,
      < 0 => 'overdue',
      0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    return when == null ? what : '$what · $when';
  }
}
