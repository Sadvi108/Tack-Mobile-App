import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/profile/application/profile_sections.dart';
import 'package:tack/features/profile/presentation/skills_card.dart';

import '../../helpers.dart';

final sampleSkills = [
  for (final name in [
    'Python',
    'Java',
    'JavaScript',
    'TypeScript',
    'C',
    'PHP',
    'HTML',
    'CSS',
    'Tailwind CSS',
    'React',
    'Next.js',
    'Node.js',
    'SQL',
    'PostgreSQL',
    'Git',
    'Docker',
    'Figma',
    'REST APIs',
    'Testing',
    'Linux',
    'Communication',
  ])
    UserSkill(
      id: name,
      skillId: name,
      name: name,
      proficiency: 3,
      source: 'self',
    ),
];

Widget card(List<UserSkill> skills) => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(TackSpace.screen),
    child: SkillsCard(skills: skills),
  ),
);

void main() {
  setUpAll(loadTackFonts);

  testWidgets(
    '21 skills have one level label and a compact eight-skill preview',
    (tester) async {
      await pumpAt(tester, card(sampleSkills));
      await tester.pumpAndSettle();
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('21 total'), findsOneWidget);
      expect(find.byType(TackProgressBar), findsNothing);
      expect(find.text('View all 21 skills'), findsOneWidget);
      expect(tester.getSize(find.byType(SkillsCard)).height, lessThan(500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every skill remains reachable and searchable in the full list', (
    tester,
  ) async {
    await pumpAt(tester, card(sampleSkills));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View all 21 skills'));
    await tester.pumpAndSettle();
    for (final skill in sampleSkills) {
      expect(find.text(skill.name), findsWidgets);
    }
    await tester.enterText(find.byType(TextField), '  TYPESCRIPT  ');
    await tester.pumpAndSettle();
    expect(find.text('TypeScript'), findsOneWidget);
    expect(find.text('Python'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not in this list');
    await tester.pumpAndSettle();
    expect(find.text('Try another skill name.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Your skills'), findsNothing);
    expect(find.text('21 total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the full list fits above the keyboard at 360px', (tester) async {
    await pumpAt(tester, card(sampleSkills));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View all 21 skills'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(find.text('Done')).dy, lessThan(640 - 260));
  });
}
