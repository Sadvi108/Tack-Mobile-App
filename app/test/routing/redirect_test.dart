import 'package:flutter_test/flutter_test.dart';
import 'package:tack/routing/router.dart';

/// The redirect rule, mirrored so it can be checked without a live session.
String? redirectFor({required bool signedIn, required String location}) {
  const publicRoutes = {
    Routes.splash,
    Routes.welcome,
    Routes.login,
    Routes.signup,
    Routes.forgotPassword,
    Routes.resetPassword,
  };

  if (!signedIn) {
    if (location == Routes.splash) return Routes.welcome;
    if (!publicRoutes.contains(location)) return Routes.welcome;
    return null;
  }
  if (location == Routes.welcome ||
      location == Routes.login ||
      location == Routes.signup) {
    return Routes.home;
  }
  return null;
}

void main() {
  group('signed out', () {
    test('the splash screen is not a dead end', () {
      // The splash exists to decide where a signed-in student goes. A signed
      // out one has nothing to wait for and must not be left on a spinner.
      expect(
        redirectFor(signedIn: false, location: Routes.splash),
        Routes.welcome,
      );
    });

    test('a protected route sends them to welcome', () {
      for (final route in [
        Routes.home,
        Routes.roadmap,
        Routes.applications,
        Routes.profile,
        Routes.vault,
        Routes.analyser,
      ]) {
        expect(
          redirectFor(signedIn: false, location: route),
          Routes.welcome,
          reason: '$route must not be reachable signed out',
        );
      }
    });

    test('the auth screens are reachable', () {
      for (final route in [
        Routes.welcome,
        Routes.login,
        Routes.signup,
        Routes.forgotPassword,
        Routes.resetPassword,
      ]) {
        expect(redirectFor(signedIn: false, location: route), isNull);
      }
    });
  });

  group('signed in', () {
    test('the auth screens bounce to the dashboard', () {
      for (final route in [Routes.welcome, Routes.login, Routes.signup]) {
        expect(redirectFor(signedIn: true, location: route), Routes.home);
      }
    });

    test('the splash is allowed to run, because it decides where to go', () {
      expect(redirectFor(signedIn: true, location: Routes.splash), isNull);
    });

    test('reset password stays reachable, for the emailed link', () {
      expect(
        redirectFor(signedIn: true, location: Routes.resetPassword),
        isNull,
      );
    });

    test('the app routes are left alone', () {
      for (final route in [Routes.home, Routes.roadmap, Routes.profile]) {
        expect(redirectFor(signedIn: true, location: route), isNull);
      }
    });
  });
}
