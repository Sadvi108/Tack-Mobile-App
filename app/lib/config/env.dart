/// Compile-time configuration.
///
/// Values arrive through `--dart-define-from-file=env/dev.json`. Nothing here
/// is a secret: the anon key is safe in a client because Row Level Security is
/// what actually protects the data. Service-role and model API keys live in
/// Supabase Edge Function secrets and never reach this package.
///
/// Product analytics and error reports stay in Tack's Supabase project.
library;

import 'package:flutter/foundation.dart';

class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// Opens the app straight onto one screen, for QA and design review.
  ///
  /// Ignored in production and in any release build, and by the auth guard,
  /// so it can show a screen but never unlock one: a signed-out student
  /// pointed at /home is still redirected to the welcome screen.
  static const initialRoute = String.fromEnvironment('INITIAL_ROUTE');

  static bool get isProduction => appEnv == 'prod';

  static String? get debugInitialRoute => initialRouteFor(
    production: isProduction,
    release: kReleaseMode,
    route: initialRoute,
  );

  /// The rule, as a pure function so it can be tested. A release build is
  /// what a student installs, whatever environment it was built against, so a
  /// QA route left in a dev define must not reach it.
  static String? initialRouteFor({
    required bool production,
    required bool release,
    required String route,
  }) => production || release || route.isEmpty ? null : route;

  /// Fails at boot rather than at the first request, so a missing define is
  /// found on the developer's machine and not by a student on a bus.
  static void assertConfigured() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing build configuration: ${missing.join(', ')}.\n'
        'Run with: flutter run --dart-define-from-file=env/dev.json',
      );
    }
  }
}
