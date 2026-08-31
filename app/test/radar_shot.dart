import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/radar/data/listing.dart';
import 'package:tack/features/radar/presentation/radar_screen.dart';

import 'features/radar/radar_screen_test.dart' as fx;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('radar with listings', (tester) async {
    await shoot(
      tester,
      const RadarScreen(),
      'radar',
      const Size(390, 844),
      overrides: fx.overrides(
        RadarResult(
          listings: [
            fx.listing(),
            fx.listing(
              id: 'l2',
              title: 'Remote React developer',
              fit: 92,
              asks: 5,
              have: 5,
              remote: true,
              matched: const ['React', 'TypeScript', 'CSS', 'HTML', 'Git'],
              missing: const [],
            ),
            fx.listing(
              id: 'l3',
              title: 'Graduate trainee programme',
              fit: null,
              asks: 0,
              have: 0,
              matched: const [],
              missing: const [],
            ),
          ],
          problems: {'careerjet': 'not configured'},
        ),
      ),
      panels: const [0, 520],
    );
  });
}
