import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/cards.dart';
import '../components/glass.dart';
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
    this.background,
    this.padBody = true,
    this.scrollable = true,
    this.onMaroonHeader = false,
    this.floatingAction,
  });

  final Widget body;
  final Widget? header;
  final Widget? pinnedCta;
  final Widget? bottomNav;

  /// Defaults to the page ground for the current palette.
  final Color? background;
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
        backgroundColor: background ?? TackColors.sailWhite,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The glass needs something behind it. A screen that brings its
            // own background has chosen a flat page, and keeps it.
            if (background == null) const TackAmbient(),
            _body(context, content),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Widget content) {
    return SafeArea(
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
                  Positioned(
                    right: TackSpace.screen,
                    bottom: TackSpace.lg,
                    child: floatingAction!,
                  ),
              ],
            ),
          ),
          if (pinnedCta != null)
            Container(
              width: double.infinity,
              // A bar of glass over the page, with a hairline where the
              // scrolling content passes under it.
              decoration: BoxDecoration(
                color: background ?? TackColors.glassBar,
                border: background == null
                    ? Border(top: BorderSide(color: TackColors.line))
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(
                TackSpace.screen,
                TackSpace.md,
                TackSpace.screen,
                TackSpace.md,
              ),
              child: pinnedCta,
            ),
          ?bottomNav,
          if (bottomNav == null)
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
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
    // No fill of its own: the header sits on the same page as the body, so the
    // glows run behind both without a band across the top.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen,
        TackSpace.sm,
        TackSpace.screen,
        TackSpace.md,
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
                TackGlassIconButton(
                  icon: TackIcons.chevronLeft,
                  iconSize: 22,
                  onTap: onBack,
                  semanticLabel: 'Back',
                ),
              if (onBack != null) const SizedBox(width: TackSpace.sm),
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
  const TackHomeHeader({
    super.key,
    required this.initials,
    this.onAvatarTap,
    this.onBellTap,
    this.unread = 0,
  });

  final String initials;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBellTap;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen,
        TackSpace.sm,
        TackSpace.screen,
        TackSpace.lg,
      ),
      child: Row(
        children: [
          const TackWordmark(),
          const Spacer(),
          if (onBellTap != null) ...[
            TackGlassIconButton(
              icon: TackIcons.bell,
              onTap: onBellTap,
              badge: unread > 0,
              semanticLabel: unread > 0
                  ? '$unread unread notifications'
                  : 'Notifications',
            ),
            const SizedBox(width: TackSpace.xs),
          ],
          TackPressable(
            onTap: onAvatarTap,
            scale: 0.9,
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            semanticLabel: 'Your profile',
            excludeSemantics: true,
            child: SizedBox(
              width: TackSpace.tapTarget,
              height: TackSpace.tapTarget,
              child: Center(child: TackAvatar(initials: initials, size: 40)),
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

/// The five destinations, and the same five in every mode.
///
/// The tab bar used to change with the student's year: juniors got four tabs,
/// final-years got a fifth. It no longer does. Year-awareness belongs in what
/// each screen leads with — a first-year still never sees a deadline — but
/// having the furniture move as well meant the app changed shape underneath a
/// student between one September and the next.
///
/// Career paths lost its tab to make room for the vault. Five is the ceiling
/// at 360px with 44px targets and labels that stay readable, so something had
/// to go. Paths is reached from the dashboard and from the roadmap, both of
/// which lead with it in the modes where it is the point.
///
/// Radar then took the Application slot rather than becoming a sixth tab, for
/// the same 360px reason. It did not displace the tracker: finding a role and
/// tracking it are one job, so tracking is the second view inside Radar, and
/// `/applications` is still a route because notifications and the readiness
/// breakdown link straight to it.
class TackTabs {
  const TackTabs._();

  static const home = TackTab(
    label: 'Home',
    icon: TackIcons.home,
    route: '/home',
  );
  static const roadmap = TackTab(
    label: 'Roadmap',
    icon: TackIcons.roadmap,
    route: '/roadmap',
  );
  static const radar = TackTab(
    label: 'Radar',
    icon: TackIcons.radar,
    route: '/radar',
  );
  static const vault = TackTab(
    label: 'Vault',
    icon: TackIcons.vault,
    route: '/vault',
  );
  static const profile = TackTab(
    label: 'Profile',
    icon: TackIcons.profile,
    route: '/profile',
  );

  static const all = <TackTab>[home, roadmap, radar, vault, profile];
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

  static const _radius = BorderRadius.all(Radius.circular(24));
  static const _height = 64.0;
  static const _inset = 5.0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    // A dock of glass floating above the bottom edge rather than a slab across
    // it. The highlight behind the current tab slides to the one tapped, so a
    // tab switch reads as moving across, not as the screen being replaced.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TackSpace.md,
        TackSpace.xs,
        TackSpace.md,
        safeBottom > 0 ? safeBottom : TackSpace.md,
      ),
      child: Container(
        height: _height,
        padding: const EdgeInsets.all(_inset),
        decoration: BoxDecoration(
          color: TackColors.glassBar,
          borderRadius: _radius,
        ),
        foregroundDecoration: TackGlass.rim(borderRadius: _radius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / tabs.length;
            return Stack(
              children: [
                if (currentIndex >= 0 && currentIndex < tabs.length)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: currentIndex.toDouble()),
                    duration: reduceMotion ? Duration.zero : TackMotion.normal,
                    curve: TackMotion.slideCurve,
                    builder: (context, at, child) => Transform.translate(
                      offset: Offset(at * width, 0),
                      child: child,
                    ),
                    child: Container(
                      width: width,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: TackColors.maroonTint,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(19),
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: _NavItem(
                          tab: tabs[i],
                          active: i == currentIndex,
                          reduceMotion: reduceMotion,
                          onTap: () {
                            if (i != currentIndex) {
                              HapticFeedback.selectionClick();
                            }
                            onTap(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.reduceMotion,
    required this.onTap,
  });

  final TackTab tab;
  final bool active;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // A small lift for the tab you are on: the icon grows into its
              // highlight as the highlight arrives.
              AnimatedScale(
                scale: active && !reduceMotion ? 1.1 : 1,
                duration: TackMotion.normal,
                curve: TackMotion.slideCurve,
                child: TackIcon(
                  tab.icon,
                  size: 20,
                  strokeWidth: active ? 2.2 : 2,
                  color: active ? TackColors.maroonText : TackColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: active ? TackText.tabLabelActive : TackText.tabLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A student's initials in a maroon disc, ringed in the brand's warm end.
///
/// The ring is what makes it read as a person rather than as another button:
/// every other round thing in the header is glass.
class TackAvatar extends StatelessWidget {
  const TackAvatar({super.key, required this.initials, this.size = 40});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = size >= 64 ? 3.0 : 2.0;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TackColors.amber, TackColors.maroon],
        ),
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TackColors.sailWhite, width: ring),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(TackColors.brandGloss, TackColors.maroon),
              TackColors.maroonDeep,
            ],
          ),
        ),
        child: Text(
          initials,
          style: TackText.cardTitle.copyWith(
            color: TackColors.onBrand,
            fontSize: size * 0.36,
            height: 1,
          ),
        ),
      ),
    );
  }
}
