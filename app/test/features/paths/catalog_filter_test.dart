import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/paths/application/catalog.dart';

CareerPath path(String slug, String title, String field, String label) =>
    CareerPath(
      id: slug,
      slug: slug,
      title: title,
      summary: 'A practical career direction',
      category: field,
      fieldSlug: field,
      fieldName: label,
    );
void main() {
  final paths = [
    path(
      'mobile',
      'Mobile app developer',
      'computer-science',
      'Computer science',
    ),
    path('cloud', 'Cloud engineer', 'computer-science', 'Computer science'),
    path('food', 'Food quality associate', 'agriculture', 'Agriculture'),
  ];
  test('every field reports its own paths without narrowing other fields', () {
    final fields = catalogFields(paths);
    expect(fields.map((f) => f.count), [1, 2]);
    expect(filterCatalog(paths, field: 'agriculture').single.slug, 'food');
    expect(filterCatalog(paths), hasLength(3));
  });
  test('case-insensitive role search combines with field choice', () {
    expect(
      filterCatalog(paths, query: 'MOBILE developer').single.slug,
      'mobile',
    );
    expect(
      filterCatalog(paths, field: 'agriculture', query: 'mobile'),
      isEmpty,
    );
    expect(filterCatalog(paths, query: 'Computer science'), hasLength(2));
  });
}
