import '../data/interview_catalog.dart';

/// The line under a suggested role that says why it was chosen. Null when the
/// student named the role themselves, because then there is nothing to explain.
String? reasonLine(RoleSuggestion suggestion) => switch (suggestion.reason) {
  RoleReason.yourPath => 'From the path you follow',
  RoleReason.yourTarget => 'From your target role',
  RoleReason.yourField || RoleReason.field =>
    suggestion.fieldName.isEmpty
        ? 'Closest match for your field'
        : 'Closest match in ${suggestion.fieldName}',
  RoleReason.general =>
    'General graduate questions. Choose a role to make them specific.',
  RoleReason.exact || RoleReason.alias || RoleReason.path => null,
};

/// How many key points a student ticked, as a sentence.
String coverageLine(int covered, int total) =>
    'You covered $covered of $total.';

/// A category as a label. Sets written before the pool hold lower-case
/// categories ("data quality"); the first letter is raised and the rest kept,
/// so "SQL" stays "SQL".
String displayCategory(String category) {
  final c = category.trim();
  if (c.isEmpty) return c;
  return c[0].toUpperCase() + c.substring(1);
}
