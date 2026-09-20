import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/radar/data/listing.dart';
import 'package:tack/features/radar/presentation/radar_screen.dart';

import 'features/radar/radar_screen_test.dart' as fx;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  for (final brightness in Brightness.values) {
    testWidgets('radar with listings ${brightness.name}', (tester) async {
      await shoot(
        tester,
        const RadarScreen(),
        'radar-${brightness.name}',
        brightness: brightness,
        const Size(360, 800),
        overrides: fx.overrides(
          RadarResult(
            listings: [
              fx.listing(),
              fx.listing(
                id: 'l2',
                title: 'Junior frontend developer',
                fit: 92,
                asks: 5,
                have: 5,
                matched: const ['React', 'TypeScript', 'CSS', 'HTML', 'Git'],
                missing: const [],
              ),
              fx.listing(
                id: 'l3',
                title: 'Marketing & Content Intern',
                kind: 'internship',
                fit: null,
                asks: 0,
                have: 0,
                matched: const [],
                missing: const [],
              ),
            ],
            problems: const {},
          ),
        ),
        panels: const [0, 520],
      );
    });
  }
}
