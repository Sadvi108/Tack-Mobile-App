import '../features/settings/presentation/sync_screen.dart';
import '../core/analytics.dart';
import '../features/toolkit/presentation/toolkit_screen.dart';
import '../features/vault/presentation/cv_check_entry_screen.dart';
import '../features/vault/presentation/cv_check_screen.dart';
export 'routes.dart';
import 'routes.dart';
import 'session_redirect.dart';
import 'tab_bar.dart';
import '../features/auth/application/session_gate.dart';
import '../features/profile/application/profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../core/supabase/client.dart';
import '../design/tack.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/password_screens.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/analyser/presentation/analyser_screen.dart';
import '../features/applications/presentation/application_detail_screen.dart';
import '../features/applications/presentation/applications_screen.dart';
import '../features/coach/presentation/coach_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/interview/presentation/interview_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/onboarding/presentation/intake_screen.dart';
import '../features/paths/presentation/path_detail_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/radar/presentation/radar_screen.dart';
import '../features/cv_builder/presentation/cv_builder_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/paths/presentation/paths_screen.dart';
import '../features/roadmap/presentation/roadmap_screen.dart';
import '../features/score/presentation/score_screen.dart';
import '../features/vault/presentation/vault_screen.dart';

/// Rebuilds the router whenever auth changes, so the redirect below re-runs.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    _subscriptions = [
      ref.listen(authStateProvider, (_, _) => notifyListeners()),
      ref.listen(profileProvider, (_, _) => notifyListeners()),
      ref.listen(passwordRecoveryProvider, (_, _) => notifyListeners()),
    ];
  }

  late final List<ProviderSubscription> _subscriptions;

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.close();
    }
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  // Screens opened from a tab cover the tab bar, as they always have. Anything
  // declared outside the shell lands here by default; a route nested inside a
  // branch names it to do the same.
  final root = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: root,
    initialLocation: Env.debugInitialRoute ?? Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final destination = sessionRedirect(
        signedIn: ref.read(supabaseProvider).auth.currentSession != null,
        location: state.matchedLocation,
        recovering: ref.read(passwordRecoveryProvider),
        onboardingComplete: ref
            .read(profileProvider)
            .value
            ?.hasFinishedOnboarding,
      );
      // Profile loading passes through splash. Resume the requested QA screen
      // only after the normal auth and onboarding guards have allowed Home.
      if (destination == Routes.home &&
          state.matchedLocation == Routes.splash &&
          Env.debugInitialRoute != null &&
          Env.debugInitialRoute != Routes.splash) {
        return Env.debugInitialRoute;
      }
      return destination;
    },
    routes: tackRoutes(
      root: root,
      onTabSelected: (index) => ref
          .read(analyticsProvider)
          .track(
            'tab_selected',
            properties: {
              'tab': TackTabs.all[index].route.substring(1),
              'mode': ref.read(modeProvider).name,
            },
          )
          .ignore(),
    ),
    errorBuilder: (context, state) => TackScaffold(
      header: TackHeader(
        title: 'Not found',
        onBack: () => context.go(Routes.home),
      ),
      body: const TackErrorState(
        title: 'That screen does not exist',
        body: 'Go back to your dashboard and try again from there.',
      ),
    ),
  );
});

/// Every route in the app, in one tree.
///
/// A function rather than inline in [routerProvider] so tests can build a
/// `GoRouter` from the real tree and prove that every location the app writes
/// resolves where it should. [root] is the navigator that screens covering the
/// tab bar land on; [onTabSelected] hears a switch to another tab.
///
/// Tools (interview, coach, analyser, CV builder) stay top-level routes:
/// pushing a location under another branch would flip the tab underneath the
/// tool, and the server already writes `/interview`.
List<RouteBase> tackRoutes({
  required GlobalKey<NavigatorState> root,
  ValueChanged<int>? onTabSelected,
}) => [
  GoRoute(
    path: Routes.splash,
    builder: (context, state) => const SplashScreen(),
  ),
  GoRoute(
    path: Routes.welcome,
    builder: (context, state) => const WelcomeScreen(),
  ),
  GoRoute(path: Routes.login, builder: (context, state) => const LoginScreen()),
  GoRoute(
    path: Routes.signup,
    builder: (context, state) => const SignUpScreen(),
  ),
  GoRoute(
    path: Routes.forgotPassword,
    builder: (context, state) => const ForgotPasswordScreen(),
  ),
  GoRoute(
    path: Routes.resetPassword,
    builder: (context, state) => const ResetPasswordScreen(),
  ),
  GoRoute(
    path: Routes.onboarding,
    builder: (context, state) => const IntakeScreen(),
  ),
  // The five tabs, in the order of TackTabs.all.
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) =>
        TackTabShell(shell: shell, onSelected: onTabSelected),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const DashboardScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.roadmap,
            builder: (context, state) => const RoadmapScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.radar,
            builder: (context, state) => const RadarScreen(),
          ),
          // Tracking is the second half of Radar, so the standalone list
          // keeps the Radar tab lit. A single application covers the bar.
          GoRoute(
            path: Routes.applications,
            builder: (context, state) => const ApplicationsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                parentNavigatorKey: root,
                builder: (context, state) =>
                    ApplicationDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          // First, so it is the branch's default location.
          GoRoute(
            path: Routes.toolkit,
            builder: (context, state) => const ToolkitScreen(),
          ),
          // The documents are the "keep" half of the toolkit, so the list
          // keeps the Toolkit tab lit, like /applications inside Radar.
          GoRoute(
            path: Routes.vault,
            builder: (context, state) => const VaultScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: Routes.paths,
    builder: (context, state) => const PathsScreen(),
    routes: [
      GoRoute(
        path: ':slug',
        builder: (context, state) =>
            PathDetailScreen(slug: state.pathParameters['slug']!),
      ),
    ],
  ),
  GoRoute(path: Routes.coach, builder: (context, state) => const CoachScreen()),
  GoRoute(path: Routes.score, builder: (context, state) => const ScoreScreen()),
  GoRoute(
    path: Routes.cvCheck,
    builder: (context, state) => const CvCheckEntryScreen(),
  ),
  GoRoute(
    path: '${Routes.cvCheck}/:id',
    builder: (context, state) =>
        CvCheckScreen(documentId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: Routes.analyser,
    builder: (context, state) => const AnalyserScreen(),
  ),
  GoRoute(
    path: Routes.interview,
    builder: (context, state) => const InterviewScreen(),
    routes: [
      // Practise again. The same screen reads its own path and opens
      // straight into the answers that are due.
      GoRoute(
        path: 'review',
        builder: (context, state) => const InterviewScreen(),
      ),
    ],
  ),
  GoRoute(
    path: Routes.settingsSync,
    builder: (context, state) => const SyncScreen(),
  ),
  GoRoute(
    path: Routes.settings,
    builder: (context, state) => const SettingsScreen(),
  ),
  GoRoute(
    path: Routes.cvBuilder,
    builder: (context, state) => const CvBuilderScreen(),
  ),
  GoRoute(
    path: Routes.notifications,
    builder: (context, state) => const NotificationsScreen(),
  ),
];

/// Goes back, and always goes somewhere.
///
/// `context.pop()` does nothing when there is nothing to pop, which leaves a
/// dead back arrow — and there is nothing to pop more often than it looks.
/// A screen opened with `context.go()` replaces the stack rather than growing
/// it; a notification tap, a deep link and a cold start on a route all arrive
/// with no history at all. The interview screen was reachable only that way,
/// so its back arrow had never worked.
///
/// [fallback] is where the student should end up when there is no history: the
/// screen they would have come from, had they come from anywhere.
void tackBack(BuildContext context, {String fallback = Routes.home}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Opens a location from anywhere, the one way every cross-screen link does.
///
/// A tab location is gone to, so the bar switches and that tab keeps its own
/// history; pushing it would stack a second copy of the tab on top. Anything
/// else covers the bar and is pushed, so back returns to whoever opened it.
void tackOpen(BuildContext context, String location) =>
    Routes.isTabLocation(location)
    ? context.go(location)
    : context.push(location);
