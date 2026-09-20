import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/profile/presentation/skills_card.dart';

import 'features/profile/skills_card_test.dart' show sampleSkills;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);
  for (final brightness in Brightness.values) {
    testWidgets('skills overview in ${brightness.name}', (tester) async {
      await shoot(
        tester,
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TackSpace.screen),
              child: SkillsCard(skills: sampleSkills),
            ),
          ),
        ),
        'skills-${brightness.name}',
        const Size(360, 540),
        brightness: brightness,
      );
    });
  }
}
