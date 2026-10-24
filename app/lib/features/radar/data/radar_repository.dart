import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'listing.dart';
import 'radar_filter.dart';

/// What Radar is looking for.
class RadarQuery {
  const RadarQuery({
    this.text = '',
    this.location = 'Dhaka',
    // Many local postings omit workplace. Show them without claiming onsite;
    // an explicitly selected workplace filter remains strict.
    this.workplace = RadarWorkplace.all,
    this.filter = RadarFilter.all,
  });

  final String text;
  final String location;
  final RadarFilter filter;
  final RadarWorkplace workplace;

  RadarQuery copyWith({
    String? text,
    String? location,
    RadarFilter? filter,
    RadarWorkplace? workplace,
  }) => RadarQuery(
    text: text ?? this.text,
    location: location ?? this.location,
    filter: filter ?? this.filter,
    workplace: workplace ?? this.workplace,
  );

  @override
  bool operator ==(Object other) =>
      other is RadarQuery &&
      other.text == text &&
      other.location == location &&
      other.filter == filter &&
      other.workplace == workplace;

  @override
  int get hashCode => Object.hash(text, location, filter, workplace);
}

/// The only thing that talks to the radar function.
///
/// The API keys for the job boards live in Edge Function secrets and are never
/// compiled into the app — the client knows a function name and nothing else.
class RadarRepository {
  const RadarRepository(this._db);

  final SupabaseClient _db;

  Future<RadarResult> search(
    RadarQuery query, {
    int offset = 0,
    bool refresh = true,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'radar',
        body: {
          'query': query.text,
          'location': query.location,
          'remote': ?query.workplace.remoteValue,
          'kind': ?query.filter.kind,
          'offset': offset,
          'refresh': refresh,
          'limit': 20,
        },
      );
      final data = res.data;
      if (data is! Map) return RadarResult.empty;
      return RadarResult.fromJson(data.cast<String, dynamic>());
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// How many listings there are of each kind.
  Future<Map<String, int>> kinds() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('radar_kinds');
      return {
        for (final e in row.entries) e.key: (e.value as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Copies a listing into the student's own tracker and returns the
  /// application id. Saving the same opening twice returns the first one.
  Future<String> save(String listingId) async {
    try {
      final id = await _db.rpc<String>(
        'save_listing',
        params: {'p_listing_id': listingId},
      );
      return id;
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final radarRepositoryProvider = Provider<RadarRepository>(
  (ref) => RadarRepository(ref.watch(supabaseProvider)),
);

/// What the student is currently searching for.
///
/// A notifier rather than a StateProvider so the query has one place that
/// changes it, and so a search does not fire on every keystroke — the screen
/// calls [RadarQueryController.submit] when the student is done typing.
class RadarQueryController extends Notifier<RadarQuery> {
  @override
  RadarQuery build() {
    ref.watch(currentUserProvider.select((user) => user?.id));
    return const RadarQuery();
  }

  void submit(RadarQuery query) => state = query;
  void setWorkplace(RadarWorkplace workplace) =>
      state = state.copyWith(workplace: workplace);
  void setFilter(RadarFilter filter) => state = state.copyWith(filter: filter);
}

final radarQueryProvider = NotifierProvider<RadarQueryController, RadarQuery>(
  RadarQueryController.new,
);

/// How many listings sit behind each chip, so a chip with nothing behind it
/// can say so rather than looking broken when it is tapped.
final radarKindsProvider = FutureProvider<Map<String, int>>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return const {};
  return ref.watch(radarRepositoryProvider).kinds();
});

final radarResultsProvider = FutureProvider<RadarResult>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return RadarResult.empty;
  final query = ref.watch(radarQueryProvider);
  return ref.watch(radarRepositoryProvider).search(query);
});

/// Immediate save feedback survives filtering and switching to Tracking.
/// Reset when the signed-in account changes; the server remains authoritative.
class RadarSavedController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    ref.watch(currentUserProvider.select((user) => user?.id));
    return const {};
  }

  void remember(String listingId, String applicationId) =>
      state = {...state, listingId: applicationId};
}

final radarSavedProvider =
    NotifierProvider<RadarSavedController, Map<String, String>>(
      RadarSavedController.new,
    );
