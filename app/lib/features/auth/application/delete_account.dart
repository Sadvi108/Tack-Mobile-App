import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/local_account_data.dart';
import '../../../core/offline/sync.dart';
import '../../../core/supabase/client.dart';
import '../data/auth_repository.dart';

/// Deletes the account on the server, then this phone's copy of it, then the
/// session.
///
/// The server deletion used to be the whole of it. The account's own database
/// on this phone (its outbox and cached rows) and any document opened in the
/// last day stayed behind for an account that no longer exists. They are only
/// erased once the server has confirmed: a deletion that failed must leave the
/// student with everything they had, including changes not yet synced.
///
/// Ordinary sign-out is unchanged; it keeps the phone's copy for next time.
Future<void> deleteAccountEverywhere(Ref ref) async {
  final uid = ref.read(currentUserProvider)?.id;
  final auth = ref.read(authRepositoryProvider);

  await auth.deleteAccount();

  if (uid != null) {
    // Close the database before its files go, so nothing writes to them as
    // they are removed. Both steps are best effort: the account is already
    // gone, and the student must still end up signed out.
    try {
      await ref.read(localDbProvider).close();
    } catch (_) {}
    try {
      await ref.read(localAccountDataProvider).erase(uid);
    } catch (_) {}
  }

  try {
    await auth.signOut();
  } catch (_) {}
}

final deleteAccountEverywhereProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => deleteAccountEverywhere(ref),
);
