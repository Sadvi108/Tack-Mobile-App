import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'oauth_provider.dart';

/// Everything that talks to Supabase Auth.
///
/// The service role key is not in this app and never will be. All of this runs
/// on the anon key plus the student's own session; Row Level Security is what
/// protects the data behind it.
/// What a sign-up attempt actually did.
enum SignUpOutcome {
  /// A confirmation email is on its way.
  confirmationSent,

  /// Confirmation is off for this project and the student is already in.
  signedIn,

  /// The address is already registered and confirmed. Supabase sends nothing
  /// in this case and says nothing about it, so the app has to.
  alreadyRegistered,
}

class AuthRepository {
  const AuthRepository(this._db);

  final SupabaseClient _db;

  /// Where Supabase sends the student back to after a Google sign-in or a
  /// password reset email. Registered in the Android manifest and the iOS
  /// Info.plist as a custom scheme.
  static const redirectUrl = 'com.tack.app://auth-callback';

  Session? get session => _db.auth.currentSession;
  User? get user => _db.auth.currentUser;

  /// The name is deliberately not asked for here. Onboarding step one asks it,
  /// and a social sign-in supplies it, so requiring it at sign-up would be a
  /// third place the same question is answered.
  ///
  /// Returns what actually happened, because "we sent you an email" is only
  /// sometimes true — see [SignUpOutcome].
  Future<SignUpOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectUrl,
      );

      // Supabase will not confirm or deny that an address is registered, so
      // signing up with an existing confirmed email returns a perfectly
      // ordinary-looking user with a fabricated id — and sends nothing. The
      // giveaway is an empty identities list. Without this check the app
      // cheerfully tells the student to check an inbox that will stay empty.
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        return SignUpOutcome.alreadyRegistered;
      }

      // A session straight away means confirmation is switched off for this
      // project, so there is no email to wait for.
      if (response.session != null) return SignUpOutcome.signedIn;

      return SignUpOutcome.confirmationSent;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Opens the system browser for a social provider.
  ///
  /// PKCE is configured at boot, so no client secret exists anywhere in the
  /// app — the secret lives in Supabase and never ships to a device.
  Future<void> signInWithProvider(TackOAuthProvider provider) async {
    try {
      await _db.auth.signInWithOAuth(
        provider.supabase,
        redirectTo: redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      // A provider that is not enabled in the dashboard yet comes back as an
      // unhelpful server error; say something the student can act on.
      if (e.message.toLowerCase().contains('provider is not enabled') ||
          e.message.toLowerCase().contains('unsupported provider')) {
        throw Failure(provider.notConfiguredMessage, cause: e);
      }
      throw Failure.from(e);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectUrl,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _db.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> resendConfirmation(String email) async {
    try {
      await _db.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: redirectUrl,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);
