import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'profile.dart';

/// Reads and writes the signed-in student's profile.
///
/// Every query is scoped by the caller's own id here, not only in the UI. Row
/// Level Security enforces the same thing server-side; this is belt and braces
/// so a future caller cannot accidentally widen the query.
class ProfileRepository {
  const ProfileRepository(this._db);

  final SupabaseClient _db;

  static const _columns = '*, cities(name), countries(name, dial_code)';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<Profile> fetch() async {
    try {
      final row = await _db
          .from('profiles')
          .select(_columns)
          .eq('id', _uid)
          .single();
      return Profile.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Partial update. `mode` is a generated column and is never sent.
  Future<Profile> update(Map<String, Object?> patch) async {
    assert(
      !patch.containsKey('mode'),
      'mode is derived server-side and cannot be written',
    );
    assert(!patch.containsKey('id'), 'a profile id cannot be changed');
    try {
      final row = await _db
          .from('profiles')
          .update(patch)
          .eq('id', _uid)
          .select(_columns)
          .single();
      return Profile.fromRow(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseProvider)),
);

/// The signed-in student's profile. Null while signed out.
final profileProvider = FutureProvider<Profile?>((ref) async {
  if (ref.watch(currentUserProvider)?.id == null) return null;
  return ref.watch(profileRepositoryProvider).fetch();
});

/// The current mode, defaulting to explore until the profile has loaded — the
/// gentlest of the four, so a slow connection never shows a first-year
/// deadline language by accident.
final modeProvider = Provider<YearMode>(
  (ref) => ref.watch(profileProvider).value?.mode ?? YearMode.explore,
);
