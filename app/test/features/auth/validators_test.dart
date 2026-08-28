import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/features/auth/data/validators.dart';

void main() {
  group('email', () {
    test('rejects an empty value with an instruction, not a complaint', () {
      expect(AuthValidators.email(''), 'Enter your email address.');
    });

    test('rejects something that is not an address', () {
      expect(AuthValidators.email('rafiq'), isNotNull);
      expect(AuthValidators.email('rafiq@'), isNotNull);
      expect(AuthValidators.email('rafiq@example'), isNotNull);
    });

    test('accepts a normal address', () {
      expect(AuthValidators.email('rafiq.hossain@du.ac.bd'), isNull);
      expect(AuthValidators.email('  rafiq+tack@gmail.com  '), isNull);
    });
  });

  group('password', () {
    test('requires at least 8 characters', () {
      expect(AuthValidators.password('short'), 'Use at least 8 characters.');
      expect(AuthValidators.password('longenough'), isNull);
    });

    test('an existing password only has to be present', () {
      expect(AuthValidators.existingPassword('abc'), isNull);
      expect(AuthValidators.existingPassword(''), isNotNull);
    });
  });

  group('Bangladeshi phone', () {
    test('accepts ten digits starting with one', () {
      expect(AuthValidators.bdPhone('1712345678'), isNull);
      expect(AuthValidators.bdPhone('171 234 5678'), isNull);
    });

    test('rejects the wrong length', () {
      expect(AuthValidators.bdPhone('17123456'), isNotNull);
      expect(AuthValidators.bdPhone('17123456789'), isNotNull);
    });

    test('rejects a number that does not start with one', () {
      expect(AuthValidators.bdPhone('2712345678'), isNotNull);
    });
  });

  group('full name', () {
    test('needs at least two characters', () {
      expect(AuthValidators.fullName('R'), isNotNull);
      expect(AuthValidators.fullName('Rafiq Hossain'), isNull);
    });
  });

  group('auth failures a student will actually hit', () {
    test('an email rate limit is explained, not blamed on them', () {
      // Supabase caps how many emails a project may send in an hour. The
      // student did nothing wrong and cannot fix it by retrying at once.
      final failure = Failure.from(
        AuthException('email rate limit exceeded', statusCode: '429'),
      );
      expect(failure.code, 'rate_limited');
      expect(failure.message, contains('Wait a little'));
      expect(failure.message.toLowerCase(), isNot(contains('error')));
    });

    test('a wrong password says what to check', () {
      final failure = Failure.from(AuthException('Invalid login credentials'));
      expect(failure.message, contains('do not match'));
    });

    test('an unconfirmed email points at the inbox', () {
      final failure = Failure.from(AuthException('Email not confirmed'));
      expect(failure.message, contains('Confirm your email'));
    });

    test('no auth message leaks a raw server string', () {
      for (final raw in [
        'Invalid login credentials',
        'email rate limit exceeded',
        'User already registered',
      ]) {
        final failure = Failure.from(AuthException(raw));
        expect(failure.message, isNot(contains(raw)));
      }
    });
  });
}
