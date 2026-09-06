import 'routes.dart';

/// The actual router rule, tested without a network or a duplicated rule.
String? sessionRedirect({
  required bool signedIn,
  required String location,
  bool recovering = false,
  bool? onboardingComplete,
}) {
  const publicRoutes = {
    Routes.welcome,
    Routes.login,
    Routes.signup,
    Routes.forgotPassword,
  };
  if (!signedIn) return publicRoutes.contains(location) ? null : Routes.welcome;
  if (recovering) {
    return location == Routes.resetPassword ? null : Routes.resetPassword;
  }
  if (onboardingComplete == null) {
    return location == Routes.splash ? null : Routes.splash;
  }
  if (!onboardingComplete) {
    return location == Routes.onboarding ? null : Routes.onboarding;
  }
  if (publicRoutes.contains(location) ||
      location == Routes.splash ||
      location == Routes.onboarding ||
      location == Routes.resetPassword) {
    return Routes.home;
  }
  return null;
}
