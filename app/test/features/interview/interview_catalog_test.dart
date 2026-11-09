import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/interview/data/interview_catalog.dart';

/// The example of contract C3.6, plus a second field.
final _example = {
  'suggested': {
    'slug': 'civil-site-engineer',
    'title': 'Civil site engineer',
    'field_slug': 'civil-engineering',
    'field_name': 'Civil engineering',
    'resolved_from': 'your_path',
  },
  'fields': [
    {
      'slug': 'civil-engineering',
      'name': 'Civil engineering',
      'roles': [
        {
          'slug': 'civil-site-engineer',
          'title': 'Civil site engineer',
          'summary':
              'Concrete, reinforcement, soil, quantities and safety on a '
              'building site.',
          'question_count': 15,
          'is_field_default': true,
          'aliases': [
            'civil engineer',
            'site engineer',
            'junior civil engineer',
          ],
        },
      ],
    },
    {
      'slug': 'computer-science',
      'name': 'Computer science and software',
      'roles': [
        {
          'slug': 'software-engineer',
          'title': 'Software engineer',
          'summary': 'Code, data structures and debugging.',
          'question_count': 15,
          'is_field_default': true,
          'aliases': ['software developer'],
        },
        {
          'slug': 'qa-engineer',
          'title': 'QA engineer',
          'summary': 'Testing and bug reports.',
          'question_count': 15,
          'is_field_default': false,
          'aliases': ['sqa engineer', 'sqa', 'software tester'],
        },
      ],
    },
  ],
};

void main() {
  test('the contract example parses in full', () {
    final catalog = InterviewCatalog.fromJson(_example);
    final suggested = catalog.suggested!;
    expect(suggested.slug, 'civil-site-engineer');
    expect(suggested.title, 'Civil site engineer');
    expect(suggested.fieldSlug, 'civil-engineering');
    expect(suggested.fieldName, 'Civil engineering');
    expect(suggested.reason, RoleReason.yourPath);

    expect(catalog.fields.map((f) => f.slug), [
      'civil-engineering',
      'computer-science',
    ]);
    final role = catalog.fields.first.roles.single;
    expect(role.questionCount, 15);
    expect(role.isFieldDefault, isTrue);
    expect(role.aliases, hasLength(3));
    expect(role.summary, startsWith('Concrete'));
    expect(catalog.allRoles, hasLength(3));
    expect(catalog.roleBySlug('qa-engineer')!.title, 'QA engineer');
    expect(catalog.roleBySlug('nope'), isNull);
  });

  test('a malformed role is dropped and an empty field with it', () {
    final catalog = InterviewCatalog.fromJson({
      'suggested': null,
      'fields': [
        {
          'slug': 'law',
          'name': 'Law',
          'roles': [
            {'slug': 'legal-associate'},
            {'title': 'No slug'},
            'garbage',
          ],
        },
        {
          'slug': 'design',
          'name': 'Design',
          'roles': [
            {'slug': 'graphic-designer', 'title': ''},
            {
              'slug': 'ui-and-ux-designer',
              'title': 'UI and UX designer',
              'question_count': '15',
              'aliases': ['ux designer', 4, ''],
            },
          ],
        },
        {'slug': 'media', 'name': 'Media'},
        {'name': 'No slug', 'roles': []},
      ],
    });
    expect(catalog.suggested, isNull);
    expect(catalog.fields.map((f) => f.slug), ['design']);
    final role = catalog.fields.single.roles.single;
    expect(role.slug, 'ui-and-ux-designer');
    expect(role.questionCount, 0);
    expect(role.aliases, ['ux designer']);
  });

  test('an unknown reason reads as general', () {
    for (final wire in ['your_cousin', null, 3]) {
      expect(RoleReason.fromWire(wire), RoleReason.general);
    }
    expect(RoleReason.fromWire('your_target'), RoleReason.yourTarget);
    expect(RoleReason.fromWire('your_field'), RoleReason.yourField);
    expect(RoleReason.fromWire('general'), RoleReason.general);
  });

  test('anything that is not a catalog is the empty one', () {
    for (final value in [
      null,
      'x',
      3,
      <Object>[],
      {'fields': 'x'},
    ]) {
      final catalog = InterviewCatalog.fromJson(value);
      expect(catalog.isEmpty, isTrue);
      expect(catalog.suggested, isNull);
    }
  });

  test('search matches titles and aliases across fields', () {
    final catalog = InterviewCatalog.fromJson(_example);
    expect(catalog.search('sqa').map((r) => r.slug), ['qa-engineer']);
    expect(catalog.search('SQA').map((r) => r.slug), ['qa-engineer']);
    expect(catalog.search('engineer').map((r) => r.slug), [
      'civil-site-engineer',
      'software-engineer',
      'qa-engineer',
    ]);
    expect(catalog.search('software').map((r) => r.slug), [
      'software-engineer',
      'qa-engineer',
    ]);
    expect(catalog.search('zzz'), isEmpty);
    expect(catalog.search('   '), isEmpty);
  });
}
