import 'package:flutter_test/flutter_test.dart';
import 'package:tack/config/env.dart';

/// The QA start route opens the app straight onto one screen. A release
/// build with it baked in would open every student's app there, so it is
/// ignored in release builds as well as in production.
void main() {
  test('a debug or profile build of a dev app uses the QA route', () {
    expect(
      Env.initialRouteFor(production: false, release: false, route: '/toolkit'),
      '/toolkit',
    );
  });

  test('a release build ignores it, whatever the environment', () {
    expect(
      Env.initialRouteFor(production: false, release: true, route: '/toolkit'),
      isNull,
    );
  });

  test('production ignores it', () {
    expect(
      Env.initialRouteFor(production: true, release: false, route: '/toolkit'),
      isNull,
    );
  });

  test('no route means none', () {
    expect(
      Env.initialRouteFor(production: false, release: false, route: ''),
      isNull,
    );
  });
}
