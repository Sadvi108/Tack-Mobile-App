import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/profile_repository.dart';
import '../data/application_models.dart';
import '../data/application_repository.dart';
import 'add_application_sheet.dart';

/// The application tracker.
///
/// A filterable list, not a kanban — horizontal scrolling loses cards at
/// 360px. The count strip doubles as the filter, so one row does two jobs.
class ApplicationsScreen extends ConsumerStatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  ConsumerState<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends ConsumerState<ApplicationsScreen> {
  TackStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final counts =
        ref.watch(applicationCountsProvider).value ?? ApplicationCounts.empty;
    final listAsync = ref.watch(applicationsProvider(_filter));
    final mode = ref.watch(modeProvider);
    final tabs = TackTabs.forMode(mode.name);
    final tabIndex = tabs.indexWhere((t) => t.route == Routes.applications);

    return TackScaffold(
      bottomNav: TackBottomNav(
        tabs: tabs,
        currentIndex: tabIndex < 0 ? 0 : tabIndex,
        onTap: (i) => context.go(tabs[i].route),
      ),
      header: const TackHeader(title: 'Applications'),
      floatingAction: TackFab(
        semanticLabel: 'Add an application',
        onPressed: () => _add(context),
        child: const TackIcon(
          TackIcons.plus,
          size: 26,
          color: TackColors.white,
        ),
      ),
      body: Column(
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
      ),
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
                      ? TackColors.danger
                      : TackColors.maroon,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _nextLine(application),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TackText.pill.copyWith(
                      color: (days ?? 1) < 0
                          ? TackColors.danger
                          : TackColors.maroon,
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
