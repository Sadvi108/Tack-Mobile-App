import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../config/env.dart';

/// Product analytics. A no-op when no key is configured, so a developer build
/// without a PostHog key still runs.
///
/// Nothing personally identifying is ever sent: no name, email, phone, CV text
/// or job description content. Only the user id and event names.
class Analytics {
  const Analytics();

  bool get _on => Env.analyticsEnabled;

  Future<void> identify(String userId, {String? mode, int? yearOfStudy}) async {
    if (!_on) return;
    await Posthog().identify(
      userId: userId,
      userProperties: {
        'mode': ?mode,
        'year_of_study': ?yearOfStudy,
      },
    );
  }

  Future<void> track(String event, {Map<String, Object>? properties}) async {
    if (!_on) return;
    await Posthog().capture(eventName: event, properties: properties);
  }

  Future<void> screen(String name) async {
    if (!_on) return;
    await Posthog().screen(screenName: name);
  }

  Future<void> reset() async {
    if (!_on) return;
    await Posthog().reset();
  }
}

final analyticsProvider = Provider<Analytics>((ref) => const Analytics());
