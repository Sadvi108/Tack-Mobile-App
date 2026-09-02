import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../../routing/tab_bar.dart';
import '../../applications/data/application_repository.dart';
import '../../applications/presentation/applications_screen.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/listing.dart';
import '../data/radar_filter.dart';
import '../data/radar_repository.dart';
import 'listing_card.dart';

/// Radar — what is open, and what of it is worth your time.
///
/// Two views in one destination, because finding a role and tracking it are
/// one job. Splitting them across two tabs made a student navigate away to
/// answer "did I already apply to this?", which is the question the feed most
/// needs to answer in place.
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  bool _tracking = false;
  late final TextEditingController _search = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The first search is the student's own target role, not an empty box.
  ///
  /// A blank search on a job board is the least useful thing an app can show
  /// somebody: Tack already knows what they said they want and which path they
  /// chose, so it asks that question for them.
  void _seedFromProfile(Profile? profile, String? pathTitle) {
    if (_seeded || profile == null) return;
    _seeded = true;
    final seed = (profile.targetRole?.trim().isNotEmpty ?? false)
        ? profile.targetRole!.trim()
        : (pathTitle ?? '');
    if (seed.isEmpty) return;
    _search.text = seed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(radarQueryProvider.notifier)
          .submit(RadarQuery(text: seed, location: profile.cityName ?? ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final feed = ref.watch(dashboardFeedProvider).value;
    _seedFromProfile(profile, feed?.primaryPathTitle);

    return TackScaffold(
      bottomNav: const TackTabBar(current: Routes.radar),
      header: TackHeader(
        title: 'Radar',
        subtitle: _tracking
            ? 'Everything you have saved or sent.'
            : 'Openings that match what you are building toward.',
      ),
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Segments(
            tracking: _tracking,
            savedCount: ref.watch(applicationCountsProvider).value?.total ?? 0,
            onChanged: (tracking) => setState(() => _tracking = tracking),
          ),
          const SizedBox(height: TackSpace.lg),
          Expanded(
            child: _tracking
                ? const SingleChildScrollView(child: ApplicationsBody())
                : _Find(controller: _search),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.tracking,
    required this.savedCount,
    required this.onChanged,
  });

  final bool tracking;
  final int savedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TackColors.white,
        borderRadius: TackRadius.pillAll,
        border: Border.all(color: TackColors.line),
      ),
      child: Row(
        children: [
          _Segment(
            label: 'Find',
            selected: !tracking,
            onTap: () => onChanged(false),
          ),
          _Segment(
            label: savedCount == 0 ? 'Tracking' : 'Tracking · $savedCount',
            selected: tracking,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: TackMotion.fast,
            curve: TackMotion.curve,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? TackColors.maroon : TackColors.white,
              borderRadius: TackRadius.pillAll,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TackText.pill.copyWith(
                fontSize: 14.5,
                color: selected ? TackColors.onBrand : TackColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Find extends ConsumerWidget {
  const _Find({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(radarQueryProvider);
    final results = ref.watch(radarResultsProvider);

    void submit() => ref
        .read(radarQueryProvider.notifier)
        .submit(query.copyWith(text: controller.text.trim()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackTextField(
          controller: controller,
          hint: 'Role, or a company',
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => submit(),
          // Inside the field, not beside it. The chips took the row that used
          // to hold a Search button, which left the keyboard's return key as
          // the only way to run a search — invisible, and unreachable at all
          // once the keyboard is dismissed.
          suffix: _SearchButton(onTap: submit),
        ),
        const SizedBox(height: TackSpace.md),
        _FilterChips(
          selected: query.filter,
          counts: ref.watch(radarKindsProvider).value ?? const {},
          onPick: (filter) =>
              ref.read(radarQueryProvider.notifier).setFilter(filter),
        ),
        const SizedBox(height: TackSpace.lg),
        Expanded(
          child: results.when(
            loading: () => const _Loading(),
            error: (_, _) => TackErrorState(
              body:
                  'Radar could not be loaded. Check your connection and try again.',
              onRetry: () => ref.invalidate(radarResultsProvider),
            ),
            data: (result) => _Results(result: result),
          ),
        ),
      ],
    );
  }
}

/// The search affordance, inside the field on the right.
///
/// A full 44px target rather than a bare 20px glyph: it sits at the very edge
/// of the screen, which is the hardest place on a phone to hit accurately.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: TackSpace.tapTarget,
          height: TackSpace.tapTarget,
          child: Center(
            child: TackIcon(
              TackIcons.search,
              size: 20,
              color: TackColors.maroonText,
            ),
          ),
        ),
      ),
    );
  }
}

/// The filter row.
///
/// Every chip carries how many listings sit behind it, and a chip with none is
/// still shown but reads as empty rather than being hidden. Hiding it would
/// leave a student wondering whether Tack does internships at all; showing
/// "Volunteer 0" answers the question honestly.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onPick,
  });

  final RadarFilter selected;
  final Map<String, int> counts;
  final void Function(RadarFilter filter) onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TackSpace.tapTarget,
      // A Row inside a scroll view rather than a horizontal ListView: seven
      // chips is far too few for laziness to buy anything, and a lazy list
      // does not build what is off the right edge — which means a screen
      // reader cannot reach "Volunteer" and neither can a test.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            for (final filter in RadarFilter.values) ...[
              if (filter != RadarFilter.values.first)
                const SizedBox(width: TackSpace.sm),
              _Chip(
                filter: filter,
                selected: filter == selected,
                count: filter == RadarFilter.all
                    ? null
                    : counts[filter.countKey],
                onTap: () => onPick(filter),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.filter,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final RadarFilter filter;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = count == 0;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? filter.label : '${filter.label}, $count listings',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          curve: TackMotion.curve,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? TackColors.maroon : TackColors.white,
            borderRadius: TackRadius.pillAll,
            border: Border.all(
              color: selected ? TackColors.maroon : TackColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filter.label,
                style: TackText.chip.copyWith(
                  fontSize: 14.5,
                  color: selected
                      ? TackColors.onBrand
                      : empty
                      ? TackColors.muted
                      : TackColors.ink,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TackText.pill.copyWith(
                    fontSize: 12.5,
                    color: selected
                        ? const Color(0xCCFFFFFF)
                        : TackColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.result});

  final RadarResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = result.listings;
    final filter = ref.watch(radarQueryProvider).filter;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Said out loud rather than shown as an empty list. "Nothing found" and
        // "the board that covers Bangladesh is not switched on" are different
        // answers, and only one of them is the student's problem.
        if (result.isMissingCareerjet) ...[
          const _BoardNotice(),
          const SizedBox(height: TackSpace.stackLoose),
        ],
        if (listings.isEmpty)
          TackEmptyState(
            title: filter == RadarFilter.all
                ? 'Nothing matched that'
                : 'No ${filter.label.toLowerCase()} right now',
            // An empty filter is usually a fact about the boards, not about
            // the student's search, and saying which is the difference between
            // "try again tomorrow" and "try different words".
            body: filter == RadarFilter.all
                ? 'Try a broader search — a role rather than a full job title.'
                : filter.emptyReason,
          )
        else
          for (final listing in listings) ...[
            ListingCard(
              listing: listing,
              onOpen: () => _open(listing.applyUrl),
              onSave: listing.isSaved
                  ? null
                  : () => _save(context, ref, listing),
              onTrack: listing.isSaved
                  ? () => context.push(
                      Routes.application(listing.savedApplicationId!),
                    )
                  : null,
            ),
            const SizedBox(height: TackSpace.stack),
          ],
        const SizedBox(height: TackSpace.xl),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    Listing listing,
  ) async {
    try {
      await ref.read(radarRepositoryProvider).save(listing.id);
      ref
        ..invalidate(radarResultsProvider)
        ..invalidate(applicationCountsProvider)
        ..invalidate(dashboardFeedProvider);
      if (context.mounted) {
        TackToast.show(context, message: 'Saved. It is in Tracking now.');
      }
    } catch (e) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: e is Failure
              ? e.message
              : 'That could not be saved. Try again in a moment.',
        );
      }
    }
  }
}

class _BoardNotice extends StatelessWidget {
  const _BoardNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.cardCompactX,
        vertical: TackSpace.cardCompactY,
      ),
      decoration: BoxDecoration(
        color: TackColors.amberTint,
        borderRadius: BorderRadius.all(TackRadius.listCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE BOARD IS OFF',
            style: TackText.monoLabelSmall.copyWith(
              color: TackColors.amberText,
            ),
          ),
          const SizedBox(height: TackSpace.sm),
          Text(
            'Careerjet covers Bangladesh and is not switched on yet, so this list '
            'is mostly roles abroad. It will fill out once it is connected.',
            style: TackText.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  /// A ListView, not a Column.
  ///
  /// Three card-sized skeletons are 420px tall, and on a 640px phone the space
  /// left under the header, the segments and the search box is about 275. As a
  /// Column that overflowed by 145px on the loading frame — the one frame
  /// every student sees. Scrolling it costs nothing and cannot overflow at any
  /// height.
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: const [
      TackSkeleton(height: 132, radius: 18),
      SizedBox(height: TackSpace.stack),
      TackSkeleton(height: 132, radius: 18),
      SizedBox(height: TackSpace.stack),
      TackSkeleton(height: 132, radius: 18),
    ],
  );
}
