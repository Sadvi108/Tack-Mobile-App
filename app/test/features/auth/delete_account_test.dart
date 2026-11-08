import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/core/offline/local_account_data.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/core/supabase/client.dart';
import 'package:tack/features/auth/application/delete_account.dart';
import 'package:tack/features/auth/data/auth_repository.dart';

/// Records what the deletion asked of the server, in order.
class _FakeAuth extends AuthRepository {
  _FakeAuth({this.fails = false})
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final bool fails;
  final calls = <String>[];

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    if (fails) throw const Failure('Your account could not be deleted.');
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
}

class _FakeLocal extends LocalAccountData {
  _FakeLocal(this.calls)
    : super(
        documents: () async => Directory.systemTemp,
        temporary: () async => Directory.systemTemp,
      );

  final List<String> calls;

  @override
  Future<void> erase(String uid) async => calls.add('erase $uid');
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-01T00:00:00Z',
);

void main() {
  ProviderContainer containerWith(_FakeAuth auth) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        currentUserProvider.overrideWithValue(_user('user-a')),
        localDbProvider.overrideWith((ref) {
          final db = LocalDb(NativeDatabase.memory(), 'user-a');
          ref.onDispose(db.close);
          return db;
        }),
        localAccountDataProvider.overrideWithValue(_FakeLocal(auth.calls)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('deletes on the server, erases this phone, then signs out', () async {
    final auth = _FakeAuth();
    final container = containerWith(auth);

    await container.read(deleteAccountEverywhereProvider)();

    expect(auth.calls, ['delete', 'erase user-a', 'signOut']);
  });

  test('a failed deletion keeps the phone copy and the session', () async {
    final auth = _FakeAuth(fails: true);
    final container = containerWith(auth);

    await expectLater(
      container.read(deleteAccountEverywhereProvider)(),
      throwsA(isA<Failure>()),
    );
    expect(auth.calls, ['delete']);
  });
}
