import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/failure.dart';

void main() {
  // The table refuses a result above its scale (0089). Edited from the profile
  // screen, that came back as "That change is not allowed from here", which
  // tells a student nothing about the number they typed.
  test('a result above its scale says what is wrong with it', () {
    final failure = Failure.from(
      const PostgrestException(
        message:
            'new row for relation "education_profiles" violates check '
            'constraint "education_profiles_gpa_within_scale"',
        code: '23514',
      ),
    );
    expect(
      failure.message,
      'That result is higher than its scale allows. A CGPA is out of 4 and '
      'a school result is out of 5.',
    );
    expect(failure.code, '23514');
  });

  test('any other refused change keeps the general message', () {
    final failure = Failure.from(
      const PostgrestException(
        message: 'violates check constraint "something_else"',
        code: '23514',
      ),
    );
    expect(failure.message, 'That change is not allowed from here.');
  });

  // functions_client throws on every non-2xx answer, so the sentence an Edge
  // Function wrote for the student arrives inside the exception. It used to be
  // dropped there, and every one of them read "Something went wrong".
  group('an Edge Function answer that is not a success', () {
    test('keeps the sentence and code the server sent', () {
      final failure = Failure.from(
        const FunctionsHttpException(
          status: 429,
          details: {
            'error': {
              'message': 'You have used today\'s AI actions.',
              'code': 'quota_exhausted',
            },
          },
        ),
      );
      expect(failure.message, 'You have used today\'s AI actions.');
      expect(failure.code, 'quota_exhausted');
      expect(failure.isOffline, isFalse);
    });

    test('keeps a sentence that came with no code', () {
      // delete-account's partial failure: the student has to know their
      // files went but the account did not.
      const sentence =
          'Your files were removed but the account itself could not be '
          'deleted. Contact us and we will finish it.';
      final failure = Failure.from(
        const FunctionsHttpException(
          status: 502,
          details: {
            'error': {'message': sentence},
          },
        ),
      );
      expect(failure.message, sentence);
      expect(failure.code, isNull);
    });

    test('a code that is not text is ignored, the sentence is kept', () {
      final failure = Failure.from(
        const FunctionsHttpException(
          status: 400,
          details: {
            'error': {'message': 'That CV is not available.', 'code': 7},
          },
        ),
      );
      expect(failure.message, 'That CV is not available.');
      expect(failure.code, isNull);
    });

    test('a spent allowance with no body still says what happened', () {
      final failure = Failure.from(const FunctionsHttpException(status: 429));
      expect(
        failure.message,
        'Today\'s AI actions are used. More arrive at midnight, Bangladesh '
        'time.',
      );
      expect(failure.code, 'quota_exhausted');
    });

    test('a signed-out answer with no body says to log in', () {
      final failure = Failure.from(
        const FunctionsHttpException(status: 401, details: 'Unauthorized'),
      );
      expect(failure.message, 'You are signed out. Log in and try again.');
      expect(failure.code, 'signed_out');
    });

    test('anything else with no body names the side it went wrong on', () {
      final failure = Failure.from(
        const FunctionsRelayException(status: 503, details: '<html>'),
      );
      expect(
        failure.message,
        'Something went wrong on our side. Try again in a moment.',
      );
      expect(failure.code, 'server_503');
    });
  });

  // "Your change is saved on this phone" was the offline message for every
  // failure, including the ones that saved nothing: a coach question, a CV
  // upload, an interview answer. Only a change that was really queued may
  // say it.
  group('offline', () {
    void neverClaimsASave(Failure failure) {
      expect(failure.isOffline, isTrue);
      expect(failure.message.toLowerCase(), isNot(contains('saved')));
      expect(failure.message.toLowerCase(), isNot(contains('sync')));
    }

    test('a request that never reached the server is offline', () {
      final failure = Failure.from(
        FunctionsFetchException(
          details: const SocketException('Failed host lookup'),
        ),
      );
      neverClaimsASave(failure);
      expect(failure.message, 'You are offline. Connect and try again.');
    });

    test('a dropped socket does not claim anything was saved', () {
      neverClaimsASave(Failure.from(const SocketException('x')));
    });

    test('a failed host lookup inside another error is offline', () {
      neverClaimsASave(
        Failure.from(
          Exception('ClientException: Failed host lookup: example.com'),
        ),
      );
    });

    test('the queued sentence is kept for changes that were queued', () {
      expect(Failure.queuedOffline.isOffline, isTrue);
      expect(
        Failure.queuedOffline.message,
        'You are offline. Your change is saved on this phone and will sync '
        'when you are back online.',
      );
      // Nothing turns into the queued sentence by being thrown.
      expect(Failure.from(Failure.queuedOffline), same(Failure.queuedOffline));
    });
  });
}
