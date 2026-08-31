import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/career_path.dart';
import '../data/path_repository.dart';
import 'compare_screen.dart';

/// Spelled out up to twelve, because "Ten real jobs" reads as a sentence
/// where "10 real jobs" reads as a label. Falls back to a plain plural while
/// the list is still loading, rather than flashing a number that then changes.
String _countWord(int? n) => switch (n) {
  null || 0 => 'Real',
  1 => 'One',
  2 => 'Two',
  3 => 'Three',
  4 => 'Four',
  5 => 'Five',
  6 => 'Six',
  7 => 'Seven',
  8 => 'Eight',
  9 => 'Nine',
  10 => 'Ten',
  11 => 'Eleven',
  12 => 'Twelve',
  _ => '$n',
};

/// The career path explorer.
///
/// Hand-written paths for the Bangladeshi market. Everything on this
/// screen works with zero model calls, so it never fails because a daily quota
/// ran out.
class PathsScreen extends ConsumerStatefulWidget {
  const PathsScreen({super.key});

  @override
  ConsumerState<PathsScreen> createState() => _PathsScreenState();
}

class _PathsScreenState extends ConsumerState<PathsScreen> {
  /// Up to two paths staged for side-by-side comparison.
  final _toCompare = <String>{};

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(pathMatchesProvider);
    final chosen = ref.watch(chosenPathsProvider).value ?? const <ChosenPath>[];
    final mode = ref.watch(modeProvider);

    return TackScaffold(
      header: TackHeader(
        title: 'Career paths',
        onBack: () => context.pop(),
        // Counted, not written down. "Ten real jobs" was true only until
        // somebody added an eleventh or retired one, and copy that states a
        // fact about the data has to read it.
        subtitle: mode == YearMode.explore
            ? '${_countWord(matchesAsync.value?.length)} real jobs, what they '
                  'pay here, and what it takes. Nothing to commit to.'
            : 'Pick up to two. Tack builds a roadmap from whichever you choose.',
      ),
      pinnedCta: _toCompare.length == 2
          ? TackButton(
              'Compare these two',
              onPressed: () {
                final ids = _toCompare.toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ComparePathsScreen(pathIdA: ids[0], pathIdB: ids[1]),
                  ),
                );
              },
            )
          : null,
      body: matchesAsync.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TackSkeleton(height: 132, radius: 18),
            SizedBox(height: TackSpace.stack),
            TackSkeleton(height: 132, radius: 18),
            SizedBox(height: TackSpace.stack),
            TackSkeleton(height: 132, radius: 18),
          ],
        ),
        error: (_, _) => TackErrorState(
          body: 'The paths did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(careerPathsProvider),
        ),
        data: (matches) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_toCompare.isNotEmpty) ...[
              Text(
                _toCompare.length == 1
                    ? 'Pick one more to compare.'
                    : 'Two picked. Compare them below.',
                style: TackText.monoLabel,
              ),
              const SizedBox(height: TackSpace.md),
            ],
            for (final match in matches) ...[
              _PathCard(
                match: match,
                following: chosen.any((c) => c.pathId == match.path.id),
                staged: _toCompare.contains(match.path.id),
                onOpen: () => context.push(Routes.path(match.path.slug)),
                onStage: () => setState(() {
                  final id = match.path.id;
                  if (_toCompare.contains(id)) {
                    _toCompare.remove(id);
                  } else if (_toCompare.length < 2) {
                    _toCompare.add(id);
                  } else {
                    // Keep the most recent pick rather than silently ignoring
                    // the tap.
                    _toCompare
                      ..remove(_toCompare.first)
                      ..add(id);
                  }
                }),
              ),
              const SizedBox(height: TackSpace.stack),
            ],
            const SizedBox(height: TackSpace.xl),
          ],
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.match,
    required this.following,
    required this.staged,
    required this.onOpen,
    required this.onStage,
  });

  final PathMatch match;
  final bool following;
  final bool staged;
  final VoidCallback onOpen;
  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final path = match.path;

    return TackCard(
      compact: true,
      emphasised: staged,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(path.title, style: TackText.cardTitle)),
              if (following)
                const TackPill('Following')
              else if (match.total > 0)
                TackPill.teal('${match.percent}% match'),
            ],
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            path.summary,
            style: TackText.bodyMuted,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: TackSpace.md),
          Row(
            children: [
              const TackIcon(TackIcons.star, size: 16, color: TackColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  path.salaryLabel,
                  style: TackText.meta.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const TackIcon(
                TackIcons.clock,
                size: 16,
                color: TackColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                '${path.timeLabel} to job-ready',
                style: TackText.meta.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          Row(
            children: [
              Expanded(
                child: TackButton.ghost(
                  staged ? 'Remove from compare' : 'Compare',
                  onPressed: onStage,
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              Expanded(
                child: TackButton.secondary('Read more', onPressed: onOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
