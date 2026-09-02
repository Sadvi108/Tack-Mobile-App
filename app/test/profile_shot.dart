import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/profile/presentation/profile_screen.dart';

import 'features/profile/profile_screen_test.dart' as fx;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('the profile header in ${brightness.name}', (tester) async {
      TackBrightness.set(brightness);
      addTearDown(() => TackBrightness.set(Brightness.light));
      await shoot(
        tester,
        const ProfileScreen(),
        'profile-${brightness.name}',
        const Size(390, 844),
        brightness: brightness,
        overrides: fx.overridesFor(fx.undergraduate(), const {}),
      );
    });
  }
}
