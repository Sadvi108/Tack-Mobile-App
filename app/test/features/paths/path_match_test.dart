import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/paths/data/career_path.dart';

PathSkill skill(String id, SkillImportance importance) =>
    PathSkill(skillId: id, name: id, importance: importance);

CareerPath pathWith(List<PathSkill> skills) => CareerPath(
  id: 'p1',
  slug: 'frontend-developer',
  title: 'Frontend developer',
  summary: 'Builds the part people see.',
  category: 'software',
  salaryMin: 25000,
  salaryMax: 45000,
  monthsToJobReady: 8,
  skills: skills,
);

void main() {
  group('matching is deterministic set comparison, never a model call', () {
    test('a student with none of the skills matches zero', () {
      final match = matchPath(
        pathWith([
          skill('html', SkillImportance.core),
          skill('css', SkillImportance.core),
        ]),
        <String>{},
      );
      expect(match.percent, 0);
      expect(match.have, isEmpty);
      expect(match.missing, hasLength(2));
    });

    test('a student with every skill matches fully', () {
      final match = matchPath(
        pathWith([
          skill('html', SkillImportance.core),
          skill('css', SkillImportance.nice),
        ]),
        {'html', 'css'},
      );
      expect(match.percent, 100);
      expect(match.missing, isEmpty);
    });

    test('a must-have counts for more than a nice-to-have', () {
      final path = pathWith([
        skill('html', SkillImportance.core),
        skill('figma', SkillImportance.nice),
      ]);

      final hasCore = matchPath(path, {'html'});
      final hasNice = matchPath(path, {'figma'});

      expect(
        hasCore.percent,
        greaterThan(hasNice.percent),
        reason: 'holding the must-have should read as a better match',
      );
      expect(hasCore.percent, 75);
      expect(hasNice.percent, 25);
    });

    test('missing must-haves are listed separately from the rest', () {
      final match = matchPath(
        pathWith([
          skill('html', SkillImportance.core),
          skill('react', SkillImportance.core),
          skill('figma', SkillImportance.nice),
        ]),
        {'html'},
      );
      expect(match.missingCore.map((s) => s.skillId), ['react']);
      expect(match.missing, hasLength(2));
    });

    test('a path with no listed skills does not divide by zero', () {
      final match = matchPath(pathWith(const []), {'html'});
      expect(match.percent, 0);
      expect(match.total, 0);
    });

    test('the same inputs always give the same answer', () {
      final path = pathWith([
        skill('html', SkillImportance.core),
        skill('css', SkillImportance.important),
        skill('figma', SkillImportance.nice),
      ]);
      final first = matchPath(path, {'html', 'figma'}).percent;
      for (var i = 0; i < 20; i++) {
        expect(matchPath(path, {'html', 'figma'}).percent, first);
      }
    });
  });

  group('presentation of money and time', () {
    test('salary is grouped with thousands separators', () {
      final path = pathWith(const []);
      expect(path.salaryLabel, '25,000–45,000 BDT a month');
    });

    test('an unknown salary says so rather than showing a zero', () {
      const path = CareerPath(
        id: 'p2',
        slug: 'x',
        title: 'X',
        summary: 'y',
        category: 'general',
      );
      expect(path.salaryLabel, 'Varies by employer');
      expect(path.timeLabel, 'Varies');
    });
  });
}
