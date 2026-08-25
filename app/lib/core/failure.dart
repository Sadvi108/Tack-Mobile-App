import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure the user is allowed to see.
///
/// Copy rules from the design handoff apply here: plain, short, sentence case,
/// never blaming the user, and always saying what to do next. Raw Postgres and
/// PostgREST messages never reach the screen.
class Failure implements Exception {
  const Failure(this.message, {this.cause, this.isOffline = false, this.code});

  final String message;
  final Object? cause;
  final bool isOffline;
  final String? code;

  static const offline = Failure(
    'You are offline. Your change is saved on this phone and will sync when you '
    'are back online.',
    isOffline: true,
  );

  /// Turns anything thrown by the data layer into something readable.
  factory Failure.from(Object error) {
    if (error is Failure) return error;

    if (error is AuthException) {
      final m = error.message.toLowerCase();
      if (m.contains('invalid login')) {
        return Failure(
          'That email and password do not match. Check both and try again.',
          cause: error,
        );
      }
      if (m.contains('already registered') ||
          m.contains('already been registered')) {
        return Failure(
          'There is already an account with that email. Log in instead.',
          cause: error,
        );
      }
      if (m.contains('email not confirmed')) {
        return Failure(
          'Confirm your email first. Check your inbox for the link we sent.',
          cause: error,
        );
      }
      if (m.contains('weak password') || m.contains('at least')) {
        return Failure(
          'Use a password of at least 8 characters.',
          cause: error,
        );
      }
      return Failure(
        'That did not work. Try again in a moment.',
        cause: error,
        code: error.statusCode,
      );
    }

    if (error is PostgrestException) {
      return switch (error.code) {
        '23505' => Failure(
          'That is already saved.',
          cause: error,
          code: error.code,
        ),
        '23503' => Failure(
          'Something it depends on is missing. Reload and try again.',
          cause: error,
          code: error.code,
        ),
        '23514' => Failure(
          'That change is not allowed from here.',
          cause: error,
          code: error.code,
        ),
        '42501' => Failure(
          'You do not have access to that.',
          cause: error,
          code: error.code,
        ),
        _ => Failure(
          'That did not save. Try again in a moment.',
          cause: error,
          code: error.code,
        ),
      };
    }

    if (error is StorageException) {
      return Failure(
        'That file did not upload. Check your connection and try again.',
        cause: error,
      );
    }

    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable')) {
      return Failure.offline;
    }

    return Failure(
      'Something went wrong. Try again in a moment.',
      cause: error,
    );
  }

  @override
  String toString() => 'Failure($message)';
}
