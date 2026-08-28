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
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/interview/presentation/interview_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/onboarding/presentation/intake_screen.dart';
import '../features/paths/presentation/path_detail_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/paths/presentation/paths_screen.dart';
import '../features/roadmap/presentation/roadmap_screen.dart';
import '../features/score/presentation/score_screen.dart';
import '../features/vault/presentation/vault_screen.dart';

/// Every route name in one place, so nothing is typed as a string literal at a
/// call site.
class Routes {
  const Routes._();

  static const splash = '/';
  static const welcome = '/welcome';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  static const onboarding = '/onboarding';

  static const home = '/home';
  static const paths = '/paths';
  static const roadmap = '/roadmap';
  static const applications = '/applications';
  static const profile = '/profile';

  static const score = '/score';
  static const vault = '/vault';
  static const analyser = '/analyser';
  static const interview = '/interview';
  static const notifications = '/notifications';

  static String application(String id) => '/applications/$id';
  static String path(String slug) => '/paths/$slug';
}

/// Rebuilds the router whenever auth changes, so the redirect below re-runs.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    _sub = ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
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
      final signedIn = ref.read(supabaseProvider).auth.currentSession != null;
      final loc = state.matchedLocation;
      const publicRoutes = {
        Routes.splash,
        Routes.welcome,
        Routes.login,
        Routes.signup,
        Routes.forgotPassword,
        Routes.resetPassword,
      };

      if (!signedIn) {
        // The splash screen exists to decide where a *signed-in* student goes.
        // A signed-out one has nothing to wait for, so send them straight on
        // rather than leaving them watching a spinner.
        if (loc == Routes.splash) return Routes.welcome;
        if (!publicRoutes.contains(loc)) return Routes.welcome;
        return null;
      }
      if (signedIn &&
          (loc == Routes.welcome ||
              loc == Routes.login ||
              loc == Routes.signup)) {
        return Routes.home;
      }
      return null;
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
