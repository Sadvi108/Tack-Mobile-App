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
            savedCount:
                ref.watch(applicationCountsProvider).value?.total ?? 0,
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
                color: selected ? TackColors.white : TackColors.muted,
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

    void submit() => ref.read(radarQueryProvider.notifier).submit(
      query.copyWith(text: controller.text.trim()),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackTextField(
          controller: controller,
          hint: 'Role, or a company',
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: TackSpace.md),
        Row(
          children: [
            _Toggle(
              label: 'Remote only',
              on: query.remoteOnly,
              onTap: () => ref
                  .read(radarQueryProvider.notifier)
                  .setRemoteOnly(value: !query.remoteOnly),
            ),
            const Spacer(),
            TackButton.ghost('Search', fullWidth: false, onPressed: submit),
          ],
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

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: TackMotion.fast,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: on ? TackColors.maroon : TackColors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: on ? TackColors.maroon : TackColors.strokeFaint,
                    width: 1.5,
                  ),
                ),
                child: on
                    ? const TackIcon(
                        TackIcons.check,
                        size: 13,
                        color: TackColors.white,
                      )
                    : null,
              ),
              const SizedBox(width: TackSpace.sm),
              Text(label, style: TackText.chip),
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
            title: 'Nothing matched that',
            body: result.isMissingCareerjet
                ? 'Only the AI jobs board is switched on, and it mostly lists senior '
                      'roles abroad. Try "remote only", or a broader search.'
                : 'Try a broader search — a role rather than a job title, or turn on '
                      'remote only.',
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
      decoration: const BoxDecoration(
        color: TackColors.amberTint,
        borderRadius: BorderRadius.all(TackRadius.listCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE BOARD IS OFF',
            style: TackText.monoLabelSmall.copyWith(color: TackColors.amberText),
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
