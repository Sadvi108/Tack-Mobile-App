import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'listing.dart';

/// What Radar is looking for.
class RadarQuery {
  const RadarQuery({this.text = '', this.location = '', this.remoteOnly = false});

  final String text;
  final String location;
  final bool remoteOnly;

  RadarQuery copyWith({String? text, String? location, bool? remoteOnly}) =>
      RadarQuery(
        text: text ?? this.text,
        location: location ?? this.location,
        remoteOnly: remoteOnly ?? this.remoteOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is RadarQuery &&
      other.text == text &&
      other.location == location &&
      other.remoteOnly == remoteOnly;

  @override
  int get hashCode => Object.hash(text, location, remoteOnly);
}

/// The only thing that talks to the radar function.
///
/// The API keys for the job boards live in Edge Function secrets and are never
/// compiled into the app — the client knows a function name and nothing else.
class RadarRepository {
  const RadarRepository(this._db);

  final SupabaseClient _db;

  Future<RadarResult> search(RadarQuery query, {int offset = 0}) async {
    try {
      final res = await _db.functions.invoke(
        'radar',
        body: {
          'query': query.text,
          'location': query.location,
          'remote': query.remoteOnly,
          'offset': offset,
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
  RadarQuery build() => const RadarQuery();

  void submit(RadarQuery query) => state = query;
  void setRemoteOnly({required bool value}) =>
      state = state.copyWith(remoteOnly: value);
}

final radarQueryProvider =
    NotifierProvider<RadarQueryController, RadarQuery>(RadarQueryController.new);

final radarResultsProvider = FutureProvider<RadarResult>((ref) async {
  if (!ref.watch(isSignedInProvider)) return RadarResult.empty;
  final query = ref.watch(radarQueryProvider);
  return ref.watch(radarRepositoryProvider).search(query);
});
