import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../design/tack.dart';

/// The bottom navigation, wired to the router.
///
/// Every root screen used to build this itself — five copies of the same
/// `indexWhere` and the same `context.go`, and one of them had already drifted
/// into needing its own guard for a tab that was not in the list. There is one
/// copy now, and a screen says only which destination it is.
///
/// It lives in routing rather than in the design system on purpose: navigating
/// is not a presentational concern, and `TackBottomNav` stays a widget that
/// draws tabs and reports taps.
class TackTabBar extends StatelessWidget {
  const TackTabBar({super.key, required this.current});

  /// The route this screen sits on, from [Routes].
  final String current;

  @override
  Widget build(BuildContext context) {
    const tabs = TackTabs.all;
    final index = tabs.indexWhere((t) => t.route == current);

    return TackBottomNav(
      tabs: tabs,
      // A screen reached from a tab but not itself a tab — career paths — keeps
      // the bar readable rather than highlighting nothing.
      currentIndex: index < 0 ? 0 : index,
      onTap: (i) {
        // Tapping the tab you are already on should do nothing, not push a
        // second copy of the screen onto the stack.
        if (tabs[i].route == current) return;
        context.go(tabs[i].route);
      },
    );
  }
}
