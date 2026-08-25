import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../crash_reporting.dart';

/// Boots Supabase. Called once, before `runApp`.
Future<void> initSupabase() async {
  Env.assertConfigured();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
    // Realtime is off by default: an always-open socket is a battery and data
    // cost the app has not yet earned.
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 2),
  );
}

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Emits on every sign-in, sign-out and token refresh.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// The signed-in user, or null. Reads the cached session synchronously so the
/// first frame does not flash the login screen at an already-signed-in user.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  final user = ref.watch(supabaseProvider).auth.currentUser;

  // So a crash can be traced to one account without naming the person behind
  // it. Signing out clears it.
  CrashReporting.setUser(user?.id);

  return user;
});

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider) != null,
);
