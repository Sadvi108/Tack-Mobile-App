/// The roles a student can practise for, grouped by career field, and the one
/// suggested to them. From `interview_catalog()` (0096), in one round trip.
///
/// Parsed defensively: a malformed role is dropped, a field left with no roles
/// is dropped, and anything that is not a catalog at all is an empty one.
library;

class InterviewRole {
  const InterviewRole({
    required this.slug,
    required this.title,
    this.summary = '',
    this.questionCount = 0,
    this.isFieldDefault = false,
    this.aliases = const [],
  });

  final String slug;
  final String title;
  final String summary;
  final int questionCount;
  final bool isFieldDefault;

  /// Other names job ads use for it, lower case.
  final List<String> aliases;

  static InterviewRole? fromJson(Object? value) {
    if (value is! Map) return null;
    final slug = value['slug'];
    final title = value['title'];
    if (slug is! String || slug.isEmpty || title is! String) return null;
    if (title.trim().isEmpty) return null;
    final summary = value['summary'];
    final count = value['question_count'];
    return InterviewRole(
      slug: slug,
      title: title,
      summary: summary is String ? summary : '',
      questionCount: count is num ? count.toInt() : 0,
      isFieldDefault: value['is_field_default'] == true,
      aliases: [
        for (final alias in (value['aliases'] as List?) ?? const [])
          if (alias is String && alias.trim().isNotEmpty) alias,
      ],
    );
  }

  /// Case-insensitive match on the title or any alias.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return title.toLowerCase().contains(q) ||
        aliases.any((a) => a.toLowerCase().contains(q));
  }
}

class InterviewField {
  const InterviewField({
    required this.slug,
    required this.name,
    required this.roles,
  });

  final String slug;
  final String name;
  final List<InterviewRole> roles;

  static InterviewField? fromJson(Object? value) {
    if (value is! Map) return null;
    final slug = value['slug'];
    final name = value['name'];
    if (slug is! String || slug.isEmpty || name is! String) return null;
    final roles = [
      for (final role in (value['roles'] as List?) ?? const [])
        ?InterviewRole.fromJson(role),
    ];
    if (roles.isEmpty) return null;
    return InterviewField(slug: slug, name: name, roles: roles);
  }
}

/// Why a role was suggested. Mirrors `resolved_from` in 0096.
enum RoleReason {
  exact,
  alias,
  path,
  field,
  yourPath,
  yourTarget,
  yourField,
  general;

  /// An unknown value from a newer server reads as general, which only ever
  /// tells the student to choose a role.
  static RoleReason fromWire(Object? value) => switch (value) {
    'exact' => RoleReason.exact,
    'alias' => RoleReason.alias,
    'path' => RoleReason.path,
    'field' => RoleReason.field,
    'your_path' => RoleReason.yourPath,
    'your_target' => RoleReason.yourTarget,
    'your_field' => RoleReason.yourField,
    _ => RoleReason.general,
  };
}

class RoleSuggestion {
  const RoleSuggestion({
    required this.slug,
    required this.title,
    required this.fieldSlug,
    required this.fieldName,
    required this.reason,
  });

  final String slug;
  final String title;
  final String fieldSlug;
  final String fieldName;
  final RoleReason reason;

  static RoleSuggestion? fromJson(Object? value) {
    if (value is! Map) return null;
    final slug = value['slug'];
    final title = value['title'];
    if (slug is! String || slug.isEmpty || title is! String) return null;
    final fieldSlug = value['field_slug'];
    final fieldName = value['field_name'];
    return RoleSuggestion(
      slug: slug,
      title: title,
      fieldSlug: fieldSlug is String ? fieldSlug : '',
      fieldName: fieldName is String ? fieldName : '',
      reason: RoleReason.fromWire(value['resolved_from']),
    );
  }
}

class InterviewCatalog {
  const InterviewCatalog({this.suggested, this.fields = const []});

  static const empty = InterviewCatalog();

  final RoleSuggestion? suggested;
  final List<InterviewField> fields;

  bool get isEmpty => fields.isEmpty;

  factory InterviewCatalog.fromJson(Object? value) {
    if (value is! Map) return empty;
    final raw = value['fields'];
    final fields = [
      if (raw is List)
        for (final field in raw) ?InterviewField.fromJson(field),
    ];
    return InterviewCatalog(
      suggested: RoleSuggestion.fromJson(value['suggested']),
      fields: fields,
    );
  }

  List<InterviewRole> get allRoles => [
    for (final field in fields) ...field.roles,
  ];

  InterviewRole? roleBySlug(String slug) {
    for (final role in allRoles) {
      if (role.slug == slug) return role;
    }
    return null;
  }

  /// Roles whose title or an alias contains [query], across every field.
  List<InterviewRole> search(String query) =>
      allRoles.where((role) => role.matches(query)).toList(growable: false);
}
