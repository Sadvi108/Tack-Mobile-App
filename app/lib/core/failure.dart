import 'dart:io';

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

  /// Nothing reached the server, and nothing was kept.
  ///
  /// This used to say the change was saved on this phone, for every offline
  /// failure: a coach question, a CV upload and an interview answer all told
  /// the student their work was safe when it had gone nowhere.
  static const offline = Failure(
    'You are offline. Connect and try again.',
    isOffline: true,
  );

  /// The one offline sentence that promises a save. Only for a change that
  /// really was written to this phone's queue, and never produced by [from].
  static const queuedOffline = Failure(
    'You are offline. Your change is saved on this phone and will sync when you '
    'are back online.',
    isOffline: true,
  );

  /// Turns anything thrown by the data layer into something readable.
  factory Failure.from(Object error) {
    if (error is Failure) return error;

    // First, because a function's own sentence is the best thing to show.
    // functions_client throws on any non-2xx answer, so every friendly message
    // an Edge Function wrote (a spent allowance, a busy queue, a deletion that
    // stopped halfway) arrives here, inside the exception.
    if (error is FunctionsFetchException) return Failure.offline;
    if (error is FunctionException) return _fromFunction(error);

    if (error is SocketException) return Failure.offline;

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
      // The project's mail sender has an hourly cap. Nothing the student did,
      // and nothing they can fix by trying again immediately.
      if (error.statusCode == '429' ||
          m.contains('rate limit') ||
          m.contains('too many requests')) {
        return Failure(
          'Too many emails have been sent from Tack in the last hour. '
          'Wait a little and try again.',
          cause: error,
          code: 'rate_limited',
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
        // The one check a student can trip by typing: a result above its
        // scale (0089). Said plainly, since they can fix it.
        '23514' when error.message.contains('gpa_within_scale') => Failure(
          'That result is higher than its scale allows. A CGPA is out of 4 '
          'and a school result is out of 5.',
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

  /// The body every Edge Function sends with a failure is
  /// `{error: {message, code?}}` (`fail()` in `_shared/util/http.ts`). That
  /// sentence is written for the student, so it is shown as it is.
  static Failure _fromFunction(FunctionException error) {
    final details = error.details;
    final body = details is Map ? details['error'] : null;
    if (body is Map && body['message'] is String) {
      final code = body['code'];
      return Failure(
        body['message'] as String,
        code: code is String ? code : null,
        cause: error,
      );
    }
    return switch (error.status) {
      429 => Failure(
        'Today\'s AI actions are used. More arrive at midnight, Bangladesh '
        'time.',
        code: 'quota_exhausted',
        cause: error,
      ),
      401 => Failure(
        'You are signed out. Log in and try again.',
        code: 'signed_out',
        cause: error,
      ),
      _ => Failure(
        'Something went wrong on our side. Try again in a moment.',
        code: 'server_${error.status}',
        cause: error,
      ),
    };
  }

  @override
  String toString() => 'Failure($message)';
}
