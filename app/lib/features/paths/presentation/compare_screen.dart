import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../data/path_repository.dart';

/// Two paths, side by side.
///
/// At 360px this cannot be two columns of prose, so it is a set of aligned
/// rows: one question down the left, both answers beside each other. That
/// keeps every comparison readable without horizontal scrolling.
class ComparePathsScreen extends ConsumerWidget {
  const ComparePathsScreen({
    super.key,
    required this.pathIdA,
    required this.pathIdB,
  });

  final String pathIdA;
  final String pathIdB;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(pathMatchesProvider);

    return TackScaffold(
      header: TackHeader(
        title: 'Compare',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: matches.when(
        loading: () => const TackSkeleton(height: 320, radius: 20),
        error: (_, _) => const TackErrorState(
          body:
              'The comparison did not load. Check your connection and try again.',
        ),
        data: (all) {
          final a = all.where((m) => m.path.id == pathIdA).firstOrNull;
          final b = all.where((m) => m.path.id == pathIdB).firstOrNull;
          if (a == null || b == null) {
            return const TackErrorState(
              body:
                  'One of those paths is no longer available. Go back and pick again.',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderRow(a: a.path.title, b: b.path.title),
              const SizedBox(height: TackSpace.md),
              TackCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.cardX,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _CompareRow(
                      label: 'How you match now',
                      a: '${a.percent}%',
                      b: '${b.percent}%',
                      highlight: true,
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Typical starting pay',
                      a: a.path.salaryLabel.replaceAll(
                        ' BDT a month',
                        '\nBDT a month',
                      ),
                      b: b.path.salaryLabel.replaceAll(
                        ' BDT a month',
                        '\nBDT a month',
                      ),
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Time to job-ready',
                      a: a.path.timeLabel,
                      b: b.path.timeLabel,
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Demand in Bangladesh',
                      a: a.path.demandLevel ?? 'Unknown',
                      b: b.path.demandLevel ?? 'Unknown',
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Skills you already have',
                      a: '${a.have.length} of ${a.total}',
                      b: '${b.have.length} of ${b.total}',
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Must-haves still missing',
                      a: '${a.missingCore.length}',
                      b: '${b.missingCore.length}',
                    ),
                    const TackDivider(),
                    _CompareRow(
                      label: 'Steps in the roadmap',
                      a: '${a.path.milestoneCount}',
                      b: '${b.path.milestoneCount}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),
              _DayToDay(title: a.path.title, items: a.path.dayToDay),
              const SizedBox(height: TackSpace.stack),
              _DayToDay(title: b.path.title, items: b.path.dayToDay),
              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.a, required this.b});

  final String a;
  final String b;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 104),
        Expanded(
          child: Text(a, style: TackText.cardTitle.copyWith(fontSize: 15)),
        ),
        const SizedBox(width: TackSpace.sm),
        Expanded(
          child: Text(b, style: TackText.cardTitle.copyWith(fontSize: 15)),
        ),
      ],
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.a,
    required this.b,
    this.highlight = false,
  });

  final String label;
  final String a;
  final String b;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = highlight
        ? TackText.cardTitle.copyWith(color: TackColors.maroon)
        : TackText.rowTitle;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: TackText.meta.copyWith(fontSize: 13.5)),
            ),
            Expanded(child: Text(a, style: style)),
            const SizedBox(width: TackSpace.sm),
            Expanded(child: Text(b, style: style)),
          ],
        ),
      ),
    );
  }
}

class _DayToDay extends StatelessWidget {
  const _DayToDay({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return TackCard(
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A day as a ${title.toLowerCase()}', style: TackText.cardTitle),
          const SizedBox(height: TackSpace.sm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 9, right: 10),
                    decoration: const BoxDecoration(
                      color: TackColors.maroon,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: Text(item, style: TackText.bodyMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
