import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// The shell every screen in Tack is built from:
///
///     [header / progress]   fixed, optional
///     [scrollable body]     flex:1, min-height:0, the only scrolling region
///     [pinned CTA]          fixed, optional
///     [bottom nav]          fixed, optional
///
/// The pinned CTA sits *outside* the scroll region. That is load-bearing: it is
/// what keeps the primary action reachable on a 640px-tall viewport, and moving
/// it into the scroll view breaks the whole layout contract.
class TackScaffold extends StatelessWidget {
  const TackScaffold({
    super.key,
    required this.body,
    this.header,
    this.pinnedCta,
    this.bottomNav,
    this.background = TackColors.sailWhite,
    this.padBody = true,
    this.scrollable = true,
    this.onMaroonHeader = false,
    this.floatingAction,
  });

  final Widget body;
  final Widget? header;
  final Widget? pinnedCta;
  final Widget? bottomNav;
  final Color background;
  final bool padBody;

  /// Whether the shell wraps [body] in its own scroll view.
  ///
  /// Set this to false when the body already scrolls — a ListView, a
  /// CustomScrollView, or anything inside a RefreshIndicator. Nesting two
  /// vertical viewports throws at layout time.
  final bool scrollable;
  final bool onMaroonHeader;
  final Widget? floatingAction;

  @override
  Widget build(BuildContext context) {
    final content = padBody
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen),
            child: body,
          )
        : body;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: onMaroonHeader ? tackSystemOverlayOnMaroon : tackSystemOverlay,
      child: Scaffold(
        backgroundColor: background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          top: !onMaroonHeader,
          child: Column(
            children: [
              ?header,
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: scrollable
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: TackSpace.xl),
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: content,
                            )
                          : content,
                    ),
                    if (floatingAction != null)
                      Positioned(right: TackSpace.screen, bottom: TackSpace.lg, child: floatingAction!),
                  ],
                ),
              ),
              if (pinnedCta != null)
                Container(
                  width: double.infinity,
                  color: background,
                  padding: const EdgeInsets.fromLTRB(
                    TackSpace.screen, TackSpace.md, TackSpace.screen, TackSpace.md,
                  ),
                  child: pinnedCta,
                ),
              ?bottomNav,
              if (bottomNav == null) SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}

/// The standard screen header: back chevron, title, optional trailing action.
class TackHeader extends StatelessWidget {
  const TackHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.subtitle,
    this.progress,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? subtitle;
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TackColors.sailWhite,
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen, TackSpace.sm, TackSpace.screen, TackSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress != null) ...[
            progress!,
            const SizedBox(height: TackSpace.lg),
          ],
          Row(
            children: [
              if (onBack != null)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: TackSpace.tapTarget,
                      height: TackSpace.tapTarget,
                      child: Center(
                        child: TackIcon(TackIcons.chevronLeft, size: 24, color: TackColors.ink),
                      ),
                    ),
                  ),
                ),
              if (onBack != null) const SizedBox(width: TackSpace.xs),
              Expanded(
                child: Text(
                  title,
                  style: TackText.screenTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: TackSpace.sm),
            Text(subtitle!, style: TackText.bodyMuted),
          ],
        ],
      ),
    );
  }
}

/// The header used on the four dashboards: wordmark on the left, avatar on the
/// right, no back affordance.
class TackHomeHeader extends StatelessWidget {
  const TackHomeHeader({super.key, required this.initials, this.onAvatarTap, this.onBellTap, this.unread = 0});

  final String initials;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBellTap;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen, TackSpace.sm, TackSpace.screen, TackSpace.lg,
      ),
      child: Row(
        children: [
          const TackWordmark(),
          const Spacer(),
          if (onBellTap != null)
            Semantics(
              button: true,
              label: unread > 0 ? '$unread unread notifications' : 'Notifications',
              child: GestureDetector(
                onTap: onBellTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: TackSpace.tapTarget,
                  height: TackSpace.tapTarget,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const TackIcon(TackIcons.bell, size: 22, color: TackColors.ink),
                      if (unread > 0)
                        Positioned(
                          top: 8,
                          right: 9,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: TackColors.maroon,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: 'Your profile',
            child: GestureDetector(
              onTap: onAvatarTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: TackColors.maroon,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TackText.pill.copyWith(color: TackColors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bottom-navigation destination.
class TackTab {
  const TackTab({required this.label, required this.icon, required this.route});

  final String label;
  final String icon;
  final String route;
}

/// Junior years get four tabs. Final year gains a fifth, Apply — applications
/// only become the point of the app once a student is actually applying.
class TackTabs {
  const TackTabs._();

  static const home = TackTab(label: 'Home', icon: TackIcons.home, route: '/home');
  static const paths = TackTab(label: 'Paths', icon: TackIcons.paths, route: '/paths');
  static const roadmap = TackTab(label: 'Roadmap', icon: TackIcons.roadmap, route: '/roadmap');
  static const apply = TackTab(label: 'Apply', icon: TackIcons.apply, route: '/applications');
  static const profile = TackTab(label: 'Profile', icon: TackIcons.profile, route: '/profile');

  static const junior = <TackTab>[home, paths, roadmap, profile];
  static const finalYear = <TackTab>[home, paths, roadmap, apply, profile];

  static List<TackTab> forMode(String mode) =>
      mode == 'launch' ? finalYear : junior;
}

class TackBottomNav extends StatelessWidget {
  const TackBottomNav({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  final List<TackTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TackColors.white,
        border: Border(top: BorderSide(color: Color(0x1423181C))),
      ),
      padding: EdgeInsets.fromLTRB(
        6, TackSpace.sm, 6, MediaQuery.paddingOf(context).bottom + 10,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == currentIndex,
                label: tabs[i].label,
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TackIcon(
                          tabs[i].icon,
                          size: 20,
                          color: i == currentIndex ? TackColors.maroon : TackColors.muted,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tabs[i].label,
                          style: i == currentIndex ? TackText.tabLabelActive : TackText.tabLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
