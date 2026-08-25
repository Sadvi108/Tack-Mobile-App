/// Compile-time configuration.
///
/// Values arrive through `--dart-define-from-file=env/dev.json`. Nothing here
/// is a secret: the anon key is safe in a client because Row Level Security is
/// what actually protects the data. Service-role and model API keys live in
/// Supabase Edge Function secrets and never reach this package.
///
/// Product analytics go to Tack's own Supabase tables. The single exception is
/// crash reporting, which goes to Sentry so that a broken release can page
/// someone — see [Env.sentryDsn] for exactly what a crash report may contain.
library;

class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// Crash reporting. Empty in development, so a developer's own crashes never
  /// land in the production issue list.
  ///
  /// This is the one place student data leaves the Supabase project, and it is
  /// deliberately narrow: a crash carries a user id, a device model and a
  /// stack trace, never a name, email, CV or anything a student typed.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Opens the app straight onto one screen, for QA and design review.
  ///
  /// Ignored in production builds and by the auth guard, so it can show a
  /// screen but never unlock one: a signed-out student pointed at /home is
  /// still redirected to the welcome screen.
  static const initialRoute = String.fromEnvironment('INITIAL_ROUTE');

  static bool get isProduction => appEnv == 'prod';

  static bool get crashReportingEnabled => sentryDsn.isNotEmpty;

  static String? get debugInitialRoute =>
      isProduction || initialRoute.isEmpty ? null : initialRoute;

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
