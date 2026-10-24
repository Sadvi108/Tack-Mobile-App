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
}
