import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/analytics.dart';

/// The property filter is the last thing standing between a careless call site
/// and a student's name sitting in a table forever, so it is tested directly.
Map<String, Object?> clean(Map<String, Object?> input) =>
    // ignore: invalid_use_of_visible_for_testing_member
    AnalyticsTestAccess.clean(input);

void main() {
  group('what is allowed through', () {
    test('counts and flags are kept', () {
      final out = clean({'count': 3, 'mode': 'launch', 'completed': true});
      expect(out, {'count': 3, 'mode': 'launch', 'completed': true});
    });

    test('unknown identifiers are rejected', () {
      final out = clean({'path_slug': 'frontend-developer', 'step': 2});
      expect(out.containsKey('path_slug'), false);
      expect(out['step'], 2);
    });
  });

  group('what is dropped', () {
    test('short personal text under an unexpected or enum key is rejected', () {
      expect(
        clean({'safe': 'a@b.com', 'screen': 'a@b.com', 'mode': 'Rafiq'}),
        isEmpty,
      );
    });
    test('anything named after personal data', () {
      final out = clean({
        'name': 'Rafiq Hossain',
        'full_name': 'Rafiq Hossain',
        'email': 'rafiq@example.com',
        'phone': '+8801712345678',
        'address': 'Dhanmondi, Dhaka',
      });
      expect(out, isEmpty);
    });

    test('free text a student wrote', () {
      final out = clean({
        'notes': 'Spoke to the recruiter on Tuesday',
        'answer': 'I once fixed a bug in production',
        'cv_text': 'Rafiq Hossain, final year student',
        'description': 'Built an inventory app',
      });
      expect(out, isEmpty);
    });

    test('a long string, whatever it is called', () {
      // A job description pasted into a property named something innocent
      // must not survive on the strength of its key alone.
      final out = clean({
        'blob':
            'We are looking for a junior frontend developer with strong '
            'JavaScript and React skills to join our Dhaka office.',
      });
      expect(out, isEmpty);
    });

    test('structured values, which are where prose hides', () {
      final out = clean({
        'skills': ['Python', 'SQL'],
        'profile': {'name': 'Rafiq'},
      });
      expect(out, isEmpty);
    });

    test('the case of the key does not matter', () {
      expect(clean({'Email': 'a@b.com', 'FULL_NAME': 'Rafiq'}), isEmpty);
    });
  });

  test('a realistic event survives with only the safe parts', () {
    final out = clean({
      'screen': 'dashboard',
      'mode': 'explore',
      'name': 'Rafiq Hossain',
      'notes': 'anything at all',
      'actions_shown': 3,
    });
    expect(out, {'screen': 'dashboard', 'mode': 'explore', 'actions_shown': 3});
  });
}
