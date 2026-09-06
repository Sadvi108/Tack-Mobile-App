import 'dart:async';
import 'package:flutter/foundation.dart';
import 'analytics.dart';

/// Error reports use Tack's own Supabase tables. Raw exception messages,
/// screenshots, device identifiers and student text are never sent.
class CrashReporting {
  const CrashReporting._();
  static Analytics? _analytics;
  static final _pending = <(Object, StackTrace?, Map<String, String>?)>[];

  static void connect(Analytics analytics) {
    _analytics = analytics;
    final pending = [..._pending];
    _pending.clear();
    for (final (error, stack, context) in pending) {
      unawaited(report(error, stack, context: context));
    }
  }

  static Future<void> run(FutureOr<void> Function() appRunner) async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        report(details.exception, details.stack, context: {'phase': 'render'}),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack, context: {'phase': 'runtime'}));
      return true;
    };
    try {
      await appRunner();
    } catch (error, stack) {
      await report(error, stack, context: {'phase': 'startup'});
      rethrow;
    }
  }

  static Future<void> report(
    Object error,
    StackTrace? stack, {
    Map<String, String>? context,
  }) async {
    final analytics = _analytics;
    if (analytics == null) {
      if (_pending.length < 10) _pending.add((error, stack, context));
      return;
    }
    await analytics.reportError(error, stack, context: context);
  }
}
