import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/application/practice_copy.dart';
import 'package:tack/features/interview/data/interview_catalog.dart';

RoleSuggestion _suggest(
  RoleReason reason, {
  String field = 'Civil engineering',
}) => RoleSuggestion(
  slug: 'civil-site-engineer',
  title: 'Civil site engineer',
  fieldSlug: 'civil-engineering',
  fieldName: field,
  reason: reason,
);

void main() {
  test('every reason has its line, or none', () {
    final lines = {
      for (final reason in RoleReason.values)
        reason: reasonLine(_suggest(reason)),
    };
    expect(lines, {
      RoleReason.exact: null,
      RoleReason.alias: null,
      RoleReason.path: null,
      RoleReason.field: 'Closest match in Civil engineering',
      RoleReason.yourPath: 'From the path you follow',
      RoleReason.yourTarget: 'From your target role',
      RoleReason.yourField: 'Closest match in Civil engineering',
      RoleReason.general:
          'General graduate questions. Choose a role to make them specific.',
    });
    expect(
      reasonLine(_suggest(RoleReason.yourField, field: '')),
      'Closest match for your field',
    );
  });

  test('coverage reads as a sentence', () {
    expect(coverageLine(2, 4), 'You covered 2 of 4.');
    expect(coverageLine(0, 3), 'You covered 0 of 3.');
  });

  test('categories are shown with a capital and nothing else changed', () {
    expect(displayCategory('data quality'), 'Data quality');
    expect(displayCategory('SQL'), 'SQL');
    expect(displayCategory('HR round'), 'HR round');
    expect(displayCategory(' css '), 'Css');
    expect(displayCategory(''), '');
  });
}
