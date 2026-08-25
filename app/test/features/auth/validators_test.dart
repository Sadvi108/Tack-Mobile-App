import 'package:flutter_test/flutter_test.dart';
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
}
