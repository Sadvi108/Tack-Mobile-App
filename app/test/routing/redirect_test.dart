import 'package:flutter_test/flutter_test.dart';
import 'package:tack/routing/routes.dart';
import 'package:tack/routing/session_redirect.dart';

void main() {
  test('signed-out sessions cannot enter protected or reset routes', () {
    for (final route in [
      Routes.home,
      Routes.splash,
      Routes.onboarding,
      Routes.resetPassword,
    ]) {
      expect(sessionRedirect(signedIn: false, location: route), Routes.welcome);
    }
    expect(sessionRedirect(signedIn: false, location: Routes.login), isNull);
  });
  test(
    'unknown profile waits and incomplete onboarding cannot be bypassed',
    () {
      expect(
        sessionRedirect(signedIn: true, location: Routes.home),
        Routes.splash,
      );
      expect(
        sessionRedirect(
          signedIn: true,
          location: Routes.login,
          onboardingComplete: false,
        ),
        Routes.onboarding,
      );
      expect(
        sessionRedirect(
          signedIn: true,
          location: Routes.home,
          onboardingComplete: false,
        ),
        Routes.onboarding,
      );
      expect(
        sessionRedirect(
          signedIn: true,
          location: Routes.onboarding,
          onboardingComplete: false,
        ),
        isNull,
      );
    },
  );
  test('password recovery takes priority over onboarding', () {
    expect(
      sessionRedirect(
        signedIn: true,
        location: Routes.home,
        recovering: true,
        onboardingComplete: false,
      ),
      Routes.resetPassword,
    );
    expect(
      sessionRedirect(
        signedIn: true,
        location: Routes.resetPassword,
        recovering: true,
      ),
      isNull,
    );
    expect(
      sessionRedirect(
        signedIn: true,
        location: Routes.resetPassword,
        onboardingComplete: true,
      ),
      Routes.home,
    );
  });
  test('completed student can open deep links and leaves onboarding', () {
    expect(
      sessionRedirect(
        signedIn: true,
        location: Routes.vault,
        onboardingComplete: true,
      ),
      isNull,
    );
    expect(
      sessionRedirect(
        signedIn: true,
        location: Routes.onboarding,
        onboardingComplete: true,
      ),
      Routes.home,
    );
  });
}
