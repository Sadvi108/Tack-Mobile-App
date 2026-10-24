import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// postgrest-dart sorts `.order('x')` newest-or-largest first unless told
/// otherwise — the opposite of the JavaScript client and of what the call
/// reads like. Twenty-three queries relied on it: the country list opened on
/// "Other" and ran Z to A, Dhaka sat at the bottom of the city list, and the
/// next-seven-days list put the furthest date first.
///
/// Every sort states its direction, so the reader never has to know the
/// default to know the order.
void main() {
  test('every .order() call says which way it sorts', () {
    final call = RegExp(r'\.order\(([^()]*)\)');
    final unstated = <String>[];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        if (match.group(1)!.contains('ascending:')) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        unstated.add('${file.path}:${line + 1} ${match.group(0)}');
      }
    }

    expect(unstated, isEmpty, reason: unstated.join('\n'));
  });
}
