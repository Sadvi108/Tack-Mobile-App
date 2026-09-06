import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/analytics.dart';

void main() {
  test('error messages cannot become telemetry', () {
    expect(
      Analytics.errorCode(StateError('student@example.com')),
      'invalid_state',
    );
    expect(
      Analytics.errorCode(Exception('Private CV text')),
      'unexpected_failure',
    );
  });
  test('only application source locations survive a stack', () {
    final safe = Analytics.safeStack(
      StackTrace.fromString(
        '#0 Student email@test.com (package:tack/features/vault/data/vault.dart:12:3)\n'
        'https://example.com/private?token=secret\n/Users/student/private.dart:1:1',
      ),
    );
    expect(safe, 'package:tack/features/vault/data/vault.dart:12:3');
  });
}
