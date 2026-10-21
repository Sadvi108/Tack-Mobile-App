// Renders the tab bar on its own page, for looking at.
//
// Deliberately not named *_test.dart, so `flutter test` does not run it.
//
//   flutter test test/nav_shot.dart
//
// The tab screens are drawn without the bar now that one shell owns it, so
// none of the other shots show it. This one does, at the 360px floor and on a
// large phone, in both palettes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';

import 'helpers.dart';
import 'shot_util.dart';

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  var _tab = 2;

  @override
  Widget build(BuildContext context) {
    return TackScaffold(
      header: const TackHomeHeader(initials: 'NJ', unread: 2),
      bottomNav: TackBottomNav(
        tabs: TackTabs.all,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good evening, Nusrat', style: TackText.screenTitle),
          const SizedBox(height: TackSpace.lg),
          TackCard(
            onTap: () {},
            child: Text('A glass card', style: TackText.cardTitle),
          ),
          const SizedBox(height: TackSpace.stackLoose),
          TackCard(
            background: TackColors.maroon,
            child: Text(
              'A brand pane',
              style: TackText.cardTitle.copyWith(color: TackColors.onBrand),
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),
          TackButton('Primary', onPressed: () {}),
          const SizedBox(height: TackSpace.md),
          TackButton.secondary('Secondary', onPressed: () {}),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(loadTackFonts);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('the dock at ${size.width.toInt()} in ${brightness.name}', (
        tester,
      ) async {
        TackBrightness.set(brightness);
        addTearDown(() => TackBrightness.set(Brightness.light));
        await shoot(
          tester,
          const _Page(),
          'nav-${size.width.toInt()}-${brightness.name}',
          size,
          brightness: brightness,
        );
      });
    }
  }
}
