import 'dart:ui' show Brightness;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/settings/data/appearance.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => TackBrightness.set(Brightness.light));

  test('a student who has never chosen follows their phone', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final appearance = await container.read(appearanceProvider.future);
    expect(appearance, Appearance.system);
    expect(appearance.mode, ThemeMode.system);
  });

  test('a choice survives the app being closed', () async {
    final first = ProviderContainer();
    await first.read(appearanceProvider.future);
    await first.read(appearanceProvider.notifier).choose(Appearance.dark);
    first.dispose();

    // A fresh container is the closest a unit test gets to a cold start.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(await second.read(appearanceProvider.future), Appearance.dark);
  });

  test('the new value is readable before the disk write finishes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appearanceProvider.future);

    // Not awaited: the tree rebuilds on this value, and a student who taps
    // "Dark" must not watch the old palette until SharedPreferences returns.
    final pending = container
        .read(appearanceProvider.notifier)
        .choose(Appearance.light);
    expect(container.read(appearanceProvider).value, Appearance.light);
    await pending;
  });

  test('a value written by an older build that we no longer ship', () async {
    SharedPreferences.setMockInitialValues({'tack.appearance': 'sepia'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appearanceProvider.future), Appearance.system);
  });

  group('the palette actually changes', () {
    test('surfaces and text invert', () {
      TackBrightness.set(Brightness.light);
      final lightCard = TackColors.white;
      final lightInk = TackColors.ink;

      TackBrightness.set(Brightness.dark);
      expect(TackColors.white, isNot(lightCard));
      expect(TackColors.ink, isNot(lightInk));
      // The card must actually be darker than the ink on it, not merely
      // different: a palette that swapped two light greys would pass `isNot`.
      expect(
        TackColors.white.computeLuminance(),
        lessThan(TackColors.ink.computeLuminance()),
      );
    });

    test('but what sits on a brand fill does not', () {
      TackBrightness.set(Brightness.light);
      final onLight = (TackColors.onBrand, TackColors.onAccent);

      TackBrightness.set(Brightness.dark);
      expect((TackColors.onBrand, TackColors.onAccent), onLight);
    });
  });
}
