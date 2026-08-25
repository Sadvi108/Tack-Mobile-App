import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env.dart';

/// Crash reporting.
///
/// The one place anything about a student leaves the Supabase project, so the
/// boundary is drawn tightly and in code rather than in a policy document:
///
///   - the user id goes, because a crash affecting one student is a different
///     problem from one affecting all of them
///   - name, email, IP address and device identifiers do not
///   - no message a student typed goes: no CV text, job description, note,
///     interview answer or search term
///
/// Everything that is not a crash — screen views, counts, feature usage —
/// stays in `public.analytics_events`.
class CrashReporting {
  const CrashReporting._();

  /// Wraps the whole app so an error anywhere is caught.
  ///
  /// With no DSN configured this runs [appRunner] directly, so a developer
  /// build works normally and never reports into the production issue list.
  static Future<void> run(FutureOr<void> Function() appRunner) async {
    if (!Env.crashReportingEnabled) {
      await _runGuarded(appRunner);
      return;
    }

    await SentryFlutter.init((options) {
      options.dsn = Env.sentryDsn;
      options.environment = Env.appEnv;

      // Never attach IP addresses, cookies or request bodies.
      options.sendDefaultPii = false;

      // Breadcrumbs are a trail of what happened before a crash. Useful,
      // but they capture widget text and console output, which is where a
      // student's own words would leak in.
      options.enableAutoNativeBreadcrumbs = false;
      options.maxBreadcrumbs = 20;

      // A student on a mid-range phone on 3G should not be paying for
      // performance traces. Errors only.
      options.tracesSampleRate = 0;
      options.enableAutoPerformanceTracing = false;

      options.attachScreenshot = false;

      options.beforeSend = _scrub;
    }, appRunner: () => _runGuarded(appRunner));
  }

  static Future<void> _runGuarded(FutureOr<void> Function() appRunner) async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (Env.crashReportingEnabled) {
        unawaited(
          Sentry.captureException(details.exception, stackTrace: details.stack),
        );
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (Env.crashReportingEnabled) {
        unawaited(Sentry.captureException(error, stackTrace: stack));
      }
      return true;
    };

    await appRunner();
  }

  /// Ties a crash to an account without identifying the person behind it.
  static Future<void> setUser(String? userId) async {
    if (!Env.crashReportingEnabled) return;
    await Sentry.configureScope(
      (scope) => scope.setUser(userId == null ? null : SentryUser(id: userId)),
    );
  }

  /// Last gate before anything leaves the device.
  ///
  /// Sentry's own settings already exclude most of this; this strips it again
  /// rather than trusting a remote default not to change under us.
  static SentryEvent? _scrub(SentryEvent event, Hint hint) {
    final user = event.user;

    // The id, and nothing that was attached alongside it.
    event.user = user == null ? null : SentryUser(id: user.id);
    event.request = null;
    event.breadcrumbs = [
      for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[])
        if (!_looksPersonal(crumb)) crumb,
    ];

    return event;
  }

  /// A breadcrumb long enough to be prose is something a student wrote.
  static bool _looksPersonal(Breadcrumb crumb) {
    final message = crumb.message ?? '';
    if (message.length > 120) return true;
    if (crumb.category == 'console' || crumb.category == 'ui.input') {
      return true;
    }
    return _personal.hasMatch(message);
  }

  static final _personal = RegExp(
    r'[\w.+-]+@[\w-]+\.[\w.-]+'
    r'|(?:\+?880[\s-]?|0)1[3-9]\d{2}[\s-]?\d{3}[\s-]?\d{3}',
  );
}

/// Test-only access to the two rules that decide what may leave the device.
@visibleForTesting
class CrashReportingTestAccess {
  const CrashReportingTestAccess._();

  static bool looksPersonal(Breadcrumb crumb) =>
      CrashReporting._looksPersonal(crumb);

  static SentryEvent? scrub(SentryEvent event) =>
      CrashReporting._scrub(event, Hint());
}
