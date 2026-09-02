import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/roadmap/data/path_suggestion.dart';
import 'package:tack/features/roadmap/presentation/roadmap_screen.dart';

import 'package:tack/features/settings/presentation/settings_screen.dart';

import 'features/roadmap/roadmap_screen_test.dart' as fx;
import 'features/settings/settings_screen_test.dart' as settings;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('settings in ${brightness.name}', (tester) async {
      TackBrightness.set(brightness);
      addTearDown(() => TackBrightness.set(Brightness.light));
      await shoot(
        tester,
        const SettingsScreen(),
        'settings-${brightness.name}',
        const Size(360, 640),
        brightness: brightness,
        overrides: settings.overrides(queued: 2),
        panels: const [0, 420, 980],
      );
    });

    testWidgets('roadmap in ${brightness.name}', (tester) async {
      TackBrightness.set(brightness);
      addTearDown(() => TackBrightness.set(Brightness.light));
      await shoot(
        tester,
        const RoadmapScreen(),
        'roadmap-${brightness.name}',
        const Size(390, 844),
        brightness: brightness,
        overrides: fx.overrides([fx.roadmap(skipped: 3)]),
      );
    });

    testWidgets('suggestions in ${brightness.name}', (tester) async {
      TackBrightness.set(brightness);
      addTearDown(() => TackBrightness.set(Brightness.light));
      await shoot(
        tester,
        const RoadmapScreen(),
        'suggest-${brightness.name}',
        const Size(390, 844),
        brightness: brightness,
        overrides: fx.overrides(
          [],
          advice: const PathAdvice(
            field: 'Computer science and software',
            unsure: true,
            suggestions: [
              PathSuggestion(
                id: '1',
                slug: 'backend-developer',
                title: 'Backend developer',
                score: 80,
                isTarget: true,
                reasons: [
                  'You said this is what you are aiming at',
                  'It is in an industry you picked',
                ],
                summary:
                    'You build the part nobody sees: the data and the '
                    'APIs the screens talk to.',
                salaryMin: 28000,
                salaryMax: 50000,
                months: 10,
                demand: 'very high',
              ),
              PathSuggestion(
                id: '2',
                slug: 'qa-engineer',
                title: 'QA engineer',
                score: 36,
                reasons: ['Your subject leads here'],
                summary: 'You find what is broken before a customer does.',
                salaryMin: 22000,
                salaryMax: 40000,
                months: 7,
                demand: 'high',
              ),
            ],
          ),
        ),
      );
    });
  }
}
