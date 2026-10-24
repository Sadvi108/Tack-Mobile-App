import '../../paths/presentation/career_field_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import 'package:tack/design/tack.dart';
import '../../../routing/router.dart';
import '../../applications/application/application_data.dart';
import '../../applications/presentation/applications_screen.dart';
import '../../dashboard/application/dashboard_data.dart';
import '../../profile/application/profile.dart';
import '../application/radar_data.dart';
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
    final current = ref.read(radarQueryProvider);
    if (current != const RadarQuery() || _search.text.isNotEmpty) {
      _search.text = current.text;
      return;
    }
    final seed = (profile.targetRole?.trim().isNotEmpty ?? false)
        ? profile.targetRole!.trim()
        : (pathTitle ?? '');
    _search.text = seed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(radarQueryProvider.notifier)
          .submit(
            RadarQuery(
              text: seed,
              location: profile.cityName?.trim().isNotEmpty == true
                  ? profile.cityName!.trim()
                  : 'Dhaka',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final feed = ref.watch(dashboardFeedProvider).value;
    _seedFromProfile(profile, feed?.primaryPathTitle);

    return TackScaffold(
      header: TackHeader(
        title: 'Radar',
        subtitle: _tracking
            ? 'Everything you have saved or sent.'
            : 'Find your next step, close to home.',
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
            height: TackSpace.tapTarget,
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

    void submit() {
      final next = query.copyWith(text: controller.text.trim());
      if (next == query) {
        ref.invalidate(radarResultsProvider);
      } else {
        ref.read(radarQueryProvider.notifier).submit(next);
      }
    }

    return RefreshIndicator(
      color: TackColors.maroonText,
      onRefresh: () async {
        ref.invalidate(radarResultsProvider);
        await ref.read(radarResultsProvider.future);
        ref.invalidate(radarKindsProvider);
      },
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          TackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Explore jobs in Bangladesh', style: TackText.cardTitle),
                const SizedBox(height: TackSpace.md),
                TackTextField(
                  controller: controller,
                  hint: 'Role, or a company',
                  maxLength: 120,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => submit(),
                  suffix: _SearchButton(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      submit();
                    },
                  ),
                ),
                const SizedBox(height: TackSpace.sm),
                TackButton.ghost(
                  'Location: ${query.location.isEmpty ? 'All locations' : query.location}',
                  onPressed: () async {
                    final location = await showTackSheet<String>(
                      context: context,
                      title: 'Choose a location',
                      child: _LocationPicker(initial: query.location),
                    );
                    if (location != null && context.mounted) {
                      ref
                          .read(radarQueryProvider.notifier)
                          .submit(
                            ref
                                .read(radarQueryProvider)
                                .copyWith(location: location),
                          );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final workplace in RadarWorkplace.values) ...[
                  if (workplace != RadarWorkplace.values.first)
                    const SizedBox(width: TackSpace.sm),
                  ChoiceChip(
                    label: Text(workplace.label),
                    labelStyle: TackText.body.copyWith(
                      color: query.workplace == workplace
                          ? TackColors.onBrand
                          : TackColors.muted,
                    ),
                    selectedColor: TackColors.maroon,
                    backgroundColor: TackColors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: TackRadius.pillAll,
                    ),
                    showCheckmark: false,
                    selected: query.workplace == workplace,
                    onSelected: (_) => ref
                        .read(radarQueryProvider.notifier)
                        .setWorkplace(workplace),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: TackSpace.sm),
          _FilterChips(
            selected: query.filter,
            onPick: (filter) =>
                ref.read(radarQueryProvider.notifier).setFilter(filter),
          ),
          const SizedBox(height: TackSpace.md),
          CareerFieldPicker(
            onPick: (path) {
              controller.text = path.title;
              ref
                  .read(radarQueryProvider.notifier)
                  .submit(query.copyWith(text: path.title));
            },
          ),
          const SizedBox(height: TackSpace.md),
          results.when(
            loading: () => const _Loading(),
            error: (_, _) => TackErrorState(
              body:
                  'Radar could not be loaded. Check your connection and try again.',
              onRetry: () => ref.invalidate(radarResultsProvider),
            ),
            data: (result) => _Results(
              key: ValueKey((query, result)),
              result: result,
              onClear: () {
                controller.clear();
                ref
                    .read(radarQueryProvider.notifier)
                    .submit(query.copyWith(text: '', filter: RadarFilter.all));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPicker extends StatefulWidget {
  const _LocationPicker({required this.initial});
  final String initial;
  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      TackSpace.screen,
      0,
      TackSpace.screen,
      MediaQuery.viewInsetsOf(context).bottom + TackSpace.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TackTextField(
                  controller: _controller,
                  label: 'City or district',
                  hint: 'For example, Dhaka',
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) => Navigator.pop(context, value.trim()),
                ),
                const SizedBox(height: TackSpace.md),
                Wrap(
                  spacing: TackSpace.sm,
                  runSpacing: TackSpace.sm,
                  children: [
                    for (final city in [
                      'Dhaka',
                      'Chattogram',
                      'Sylhet',
                      'Rajshahi',
                      'Khulna',
                      'Bangladesh',
                    ])
                      ActionChip(
                        label: Text(city, style: TackText.body),
                        onPressed: () => Navigator.pop(context, city),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TackSpace.lg),
        TackButton(
          'Use this location',
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
        ),
      ],
    ),
  );
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

/// Employment type is independent of workplace and city.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onPick});

  final RadarFilter selected;
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
    required this.onTap,
  });

  final RadarFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: filter.label,
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
                  color: selected ? TackColors.onBrand : TackColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerStatefulWidget {
  const _Results({super.key, required this.result, required this.onClear});
  final RadarResult result;
  final VoidCallback onClear;
  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  late final List<Listing> _listings = [...widget.result.listings];
  late int _offset = _listings.length;
  late bool _hasMore = _listings.length == 20;
  bool _loadingMore = false;
  bool _pageFailed = false;
  final Set<String> _saving = {};

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(radarQueryProvider);
    final problems = widget.result.problems;
    final saved = ref.watch(radarSavedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_listings.length}${_hasMore ? '+' : ''} openings',
                style: TackText.cardTitle,
              ),
            ),
            TackButton.ghost(
              'Refresh',
              fullWidth: false,
              onPressed: () => ref.invalidate(radarResultsProvider),
            ),
          ],
        ),
        Text(
          '${query.workplace.label} · ${query.location.isEmpty ? 'All locations' : query.location} · Ranked by skill fit',
          style: TackText.bodyMuted,
        ),
        const SizedBox(height: TackSpace.md),
        if (problems.isNotEmpty) ...[
          _BoardNotice(result: widget.result),
          const SizedBox(height: TackSpace.md),
        ],
        if (_listings.isEmpty) ...[
          TackEmptyState(
            title: query.filter == RadarFilter.all
                ? 'Try a wider search'
                : 'No ${query.filter.label.toLowerCase()} right now',
            body: query.filter == RadarFilter.all
                ? 'Try a shorter role name or choose another city. You can also explore remote work.'
                : query.filter.emptyReason,
          ),
          TackButton.secondary(
            'Clear role and job type',
            onPressed: widget.onClear,
          ),
        ] else
          for (final listing in _listings) ...[
            ListingCard(
              listing: listing,
              saving: _saving.contains(listing.id),
              onOpen: () => _open(listing.applyUrl),
              onSave: listing.isSaved || saved.containsKey(listing.id)
                  ? null
                  : () => _save(listing),
              onTrack: listing.isSaved || saved.containsKey(listing.id)
                  ? () => context.push(
                      Routes.application(
                        saved[listing.id] ?? listing.savedApplicationId!,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: TackSpace.stack),
          ],
        if (_hasMore)
          TackButton.secondary(
            _pageFailed ? 'Try loading more again' : 'Load more openings',
            loading: _loadingMore,
            onPressed: _loadMore,
          ),
        const SizedBox(height: TackSpace.xl),
      ],
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _pageFailed = false;
    });
    try {
      final page = await ref
          .read(radarRepositoryProvider)
          .search(
            ref.read(radarQueryProvider),
            offset: _offset,
            refresh: false,
          );
      if (!mounted) return;
      setState(() {
        _offset += page.listings.length;
        final ids = _listings.map((l) => l.id).toSet();
        _listings.addAll(page.listings.where((l) => ids.add(l.id)));
        _hasMore = page.listings.length == 20;
      });
    } catch (_) {
      if (mounted) setState(() => _pageFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    try {
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('unavailable');
      }
    } catch (_) {
      if (mounted) {
        TackToast.show(
          context,
          message: 'This posting could not be opened. Try again shortly.',
        );
      }
    }
  }

  Future<void> _save(Listing listing) async {
    if (!_saving.add(listing.id)) return;
    setState(() {});
    try {
      final id = await ref.read(radarRepositoryProvider).save(listing.id);
      if (!mounted) return;
      ref.read(radarSavedProvider.notifier).remember(listing.id, id);
      ref
        ..invalidate(applicationCountsProvider)
        ..invalidate(applicationsProvider)
        ..invalidate(dashboardFeedProvider);
      TackToast.show(context, message: 'Saved. It is in Tracking now.');
    } catch (e) {
      if (mounted) {
        TackToast.show(
          context,
          message: e is Failure
              ? e.message
              : 'That could not be saved. Try again in a moment.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(listing.id));
    }
  }
}

class _BoardNotice extends StatelessWidget {
  const _BoardNotice({required this.result});

  final RadarResult result;

  /// "A", "A and B", "A, B and C".
  static String _join(List<String> names) => names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  /// Names the boards, because "some sources" tells nobody — student or
  /// whoever runs Tack — whether to wait or to go and set a key.
  String get _message {
    final notSetUp = result.notSetUp;
    final unreachable = result.unreachable;
    if (notSetUp.isEmpty && unreachable.isEmpty) {
      return 'Showing available postings. Some sources could not be '
          'refreshed; try again later.';
    }
    return [
      result.isMissingBangladesh
          ? 'Bangladesh coverage is limited right now.'
          : 'Showing postings from the other boards.',
      if (notSetUp.isNotEmpty)
        '${_join(notSetUp)} ${notSetUp.length == 1 ? 'is' : 'are'} not set '
            'up yet.',
      if (unreachable.isNotEmpty)
        '${_join(unreachable)} could not be reached. Try again later.',
    ].join(' ');
  }

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
            'Some sources are unavailable',
            style: TackText.monoLabelSmall.copyWith(
              color: TackColors.amberText,
            ),
          ),
          const SizedBox(height: TackSpace.sm),
          Text(_message, style: TackText.bodyMuted),
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
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
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
