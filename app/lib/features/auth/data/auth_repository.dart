import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';

/// Everything that talks to Supabase Auth.
///
/// The service role key is not in this app and never will be. All of this runs
/// on the anon key plus the student's own session; Row Level Security is what
/// protects the data behind it.
class AuthRepository {
  const AuthRepository(this._db);

  final SupabaseClient _db;

  /// Where Supabase sends the student back to after a Google sign-in or a
  /// password reset email. Registered in the Android manifest and the iOS
  /// Info.plist as a custom scheme.
  static const redirectUrl = 'com.tack.app://auth-callback';

  Session? get session => _db.auth.currentSession;
  User? get user => _db.auth.currentUser;

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      await _db.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectUrl,
        data: {'full_name': fullName.trim()},
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Opens the system browser for Google. PKCE is configured at boot, so no
  /// client secret exists anywhere in the app.
  Future<void> signInWithGoogle() async {
    try {
      await _db.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim(), redirectTo: redirectUrl);
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
      await _db.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: redirectUrl);
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

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));
