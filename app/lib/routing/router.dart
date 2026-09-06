import '../features/settings/presentation/sync_screen.dart';
import '../features/vault/presentation/cv_check_screen.dart';
export 'routes.dart';
import 'routes.dart';
import 'session_redirect.dart';
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

  return GoRouter(
    initialLocation: Env.debugInitialRoute ?? Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      return sessionRedirect(
        signedIn: ref.read(supabaseProvider).auth.currentSession != null,
        location: state.matchedLocation,
        recovering: ref.read(passwordRecoveryProvider),
        onboardingComplete: ref
            .read(profileProvider)
            .value
            ?.hasFinishedOnboarding,
      );
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
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
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const DashboardScreen(),
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
      GoRoute(
        path: Routes.roadmap,
        builder: (context, state) => const RoadmapScreen(),
      ),
      GoRoute(
        path: Routes.coach,
        builder: (context, state) => const CoachScreen(),
      ),
      GoRoute(
        path: Routes.radar,
        builder: (context, state) => const RadarScreen(),
      ),
      GoRoute(
        path: Routes.applications,
        builder: (context, state) => const ApplicationsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                ApplicationDetailScreen(id: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.score,
        builder: (context, state) => const ScoreScreen(),
      ),
      GoRoute(
        path: '/vault/check/:id',
        builder: (context, state) =>
            CvCheckScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.vault,
        builder: (context, state) => const VaultScreen(),
      ),
      GoRoute(
        path: Routes.analyser,
        builder: (context, state) => const AnalyserScreen(),
      ),
      GoRoute(
        path: Routes.interview,
        builder: (context, state) => const InterviewScreen(),
      ),
      GoRoute(
        path: '/settings/sync',
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
    ],
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
