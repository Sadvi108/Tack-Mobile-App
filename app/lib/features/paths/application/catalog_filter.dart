import '../data/career_path.dart';

List<({String slug, String name, int count})> catalogFields(
  List<CareerPath> paths,
) {
  final fields = <String, ({String slug, String name, int count})>{};
  for (final path in paths) {
    final slug = path.fieldSlug ?? path.category;
    final previous = fields[slug];
    fields[slug] = (
      slug: slug,
      name: path.fieldName ?? path.category,
      count: (previous?.count ?? 0) + 1,
    );
  }
  return fields.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

List<CareerPath> filterCatalog(
  List<CareerPath> paths, {
  String field = '',
  String query = '',
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  return paths
      .where(
        (path) =>
            (field.isEmpty || (path.fieldSlug ?? path.category) == field) &&
            terms.every(
              (term) =>
                  '${path.title} ${path.summary} ${path.fieldName ?? path.category}'
                      .toLowerCase()
                      .contains(term),
            ),
      )
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}
