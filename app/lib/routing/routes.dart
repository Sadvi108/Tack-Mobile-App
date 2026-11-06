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

  static const toolkit = '/toolkit';
  static const interviewReview = '/interview/review';
  static const cvCheck = '/vault/check';
  static String cvCheckFor(String id) => '/vault/check/$id';
  static const settingsSync = '/settings/sync';

  static String application(String id) => '/applications/$id';
  static String path(String slug) => '/paths/$slug';

  /// Locations inside a tab's branch: reached with go, so the tab switches and
  /// keeps its own history. Anything else covers the bar and is pushed.
  static const tabLocations = {
    home,
    roadmap,
    radar,
    applications,
    toolkit,
    vault,
    profile,
  };
  static bool isTabLocation(String location) =>
      tabLocations.contains(Uri.parse(location).path);
}
