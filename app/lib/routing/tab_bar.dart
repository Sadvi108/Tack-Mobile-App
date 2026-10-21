import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/tack.dart';

/// The bottom navigation and the five tab roots under it, wired to the router.
///
/// Every root screen used to draw this bar itself and switch tabs with
/// `context.go`. That made a tab switch a page transition: the bar slid away
/// with the screen it belonged to while a second copy slid in, and whatever the
/// student had scrolled to or filtered was thrown away. Each tab is now a
/// branch of a `StatefulShellRoute`, kept alive in an `IndexedStack`, and this
/// is the one bar — so a tab is where you left it and the bar never moves.
///
/// It lives in routing rather than in the design system on purpose: navigating
/// is not a presentational concern, and `TackBottomNav` stays a widget that
/// draws tabs and reports taps.
class TackTabShell extends StatelessWidget {
  const TackTabShell({super.key, required this.shell});

  /// Branches are in the order of [TackTabs.all].
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TackColors.sailWhite,
      // Each tab brings its own TackScaffold. Scaffold gives it the space above
      // the bar with the bottom safe area already spent by the bar, and with
      // the keyboard inset already taken, so neither is counted twice.
      body: shell,
      // Scaffold offers its bottom bar the full screen height, and the bar's
      // tabs grow to fill whatever they are offered. The Column hands it an
      // unbounded height instead, as TackScaffold's Column always did, so it
      // is only as tall as its tabs.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TackBottomNav(
            tabs: TackTabs.all,
            currentIndex: shell.currentIndex,
            // Tapping the tab you are on takes you to its first screen — Radar
            // from the applications list — rather than doing nothing.
            onTap: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
          ),
        ],
      ),
    );
  }
}
