/// Compile-time configuration.
///
/// Values arrive through `--dart-define-from-file=env/dev.json`. Nothing here
/// is a secret: the anon key is safe in a client because Row Level Security is
/// what actually protects the data. Service-role and model API keys live in
/// Supabase Edge Function secrets and never reach this package.
library;

class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const posthogKey = String.fromEnvironment('POSTHOG_KEY');
  static const posthogHost =
      String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://eu.i.posthog.com');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isProduction => appEnv == 'prod';
  static bool get analyticsEnabled => posthogKey.isNotEmpty;
  static bool get crashReportingEnabled => sentryDsn.isNotEmpty;

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
