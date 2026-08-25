import 'package:supabase_flutter/supabase_flutter.dart';

/// The social sign-ins Tack offers.
///
/// Google leads because most Bangladeshi students already have an account and
/// every tap saved at sign-up is a student who does not abandon it. Facebook
/// is second for the same reason — it is the most-used account in the country.
/// GitHub is there for the software paths, where having one is itself a signal.
enum TackOAuthProvider {
  google,
  facebook,
  github;

  OAuthProvider get supabase => switch (this) {
    TackOAuthProvider.google => OAuthProvider.google,
    TackOAuthProvider.facebook => OAuthProvider.facebook,
    TackOAuthProvider.github => OAuthProvider.github,
  };

  String get label => switch (this) {
    TackOAuthProvider.google => 'Google',
    TackOAuthProvider.facebook => 'Facebook',
    TackOAuthProvider.github => 'GitHub',
  };

  /// Shown when a provider is not switched on in the Supabase dashboard yet.
  /// Without this the student sees a raw "Unsupported provider" from the
  /// server, which tells them nothing and looks like their fault.
  String get notConfiguredMessage =>
      '$label sign-in is not switched on yet. Use email, or another option.';
}
