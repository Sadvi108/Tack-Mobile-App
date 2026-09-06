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
  static const radar = '/radar';
  static const coach = '/coach';
  static const applications = '/applications';
  static const profile = '/profile';

  static const score = '/score';
  static const vault = '/vault';
  static const analyser = '/analyser';
  static const interview = '/interview';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const cvBuilder = '/cv-builder';

  static String application(String id) => '/applications/$id';
  static String path(String slug) => '/paths/$slug';
}
