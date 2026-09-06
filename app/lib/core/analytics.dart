import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase/client.dart';

/// Product analytics, stored in Tack's own database.
///
/// There is no third-party analytics service. Events go to
/// `public.analytics_events` in the same Supabase project as everything else,
/// under the student's own session, so Row Level Security applies to them like
/// any other row and closing an account takes the history with it.
///
/// What is never sent: names, email addresses, phone numbers, CV text, job
/// description text, notes, answers. Event names and counts only. If a
/// property would identify a student to someone reading the table, it does not
/// belong in it.
class Analytics {
  Analytics(this._db);

  final SupabaseClient _db;

  /// Events are batched so a tap does not cost a round trip on a slow
  /// connection, and flushed on a timer or when the buffer fills.
  final List<Map<String, Object?>> _buffer = [];
  Timer? _flushTimer;
  String? _appVersion;

  static const _maxBuffer = 20;
  static const _flushEvery = Duration(seconds: 30);

  String? get _uid => _db.auth.currentUser?.id;

  Future<void> track(String name, {Map<String, Object?>? properties}) async {
    final userId = _uid;
    if (userId == null || !_events.contains(name)) return;

    _appVersion ??= await _version();

    _buffer.add({
      'user_id': userId,
      'name': name,
      'properties': _clean(properties ?? const {}),
      'app_version': _appVersion,
      'platform': defaultTargetPlatform.name,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (_buffer.length >= _maxBuffer) {
      await flush();
    } else {
      _flushTimer ??= Timer(_flushEvery, flush);
    }
  }

  Future<void> screen(String name) =>
      track('screen_view', properties: {'screen': name});

  /// Sends whatever is buffered. Failures are dropped rather than retried:
  /// analytics must never cost a student their work, and a lost event is not
  /// worth a queue.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;

    final batch = _buffer.where((row) => row['user_id'] == _uid).toList();
    _buffer.clear();

    try {
      if (batch.isNotEmpty) await _db.from('analytics_events').insert(batch);
    } catch (_) {
      // Deliberately silent.
    }
  }

  /// Records an error for later diagnosis. Same rule: no personal data, and a
  /// failure here is swallowed.
  Future<void> reportError(
    Object error,
    StackTrace? stack, {
    Map<String, Object?>? context,
  }) async {
    if (_uid == null) return;
    _appVersion ??= await _version();
    try {
      await _db.rpc(
        'record_client_error',
        params: {
          'p_code': errorCode(error),
          'p_stack': safeStack(stack),
          'p_context': _clean(context ?? const {}),
          'p_version': _appVersion,
          'p_platform': defaultTargetPlatform.name,
        },
      );
    } catch (_) {
      /* Reporting must never interrupt the student's work. */
    }
  }

  static String errorCode(Object error) => switch (error) {
    FormatException() => 'invalid_data',
    StateError() => 'invalid_state',
    ArgumentError() => 'invalid_argument',
    FlutterError() => 'render_failure',
    _ => 'unexpected_failure',
  };

  static String? safeStack(StackTrace? stack) {
    if (stack == null) return null;
    return RegExp(
      r'package:tack/[a-zA-Z0-9_/]+\.dart:\d+:\d+',
    ).allMatches(stack.toString()).take(20).map((m) => m[0]).join('\n');
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<String> _version() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  static const _events = {
    'screen_view',
    'onboarding_started',
    'onboarding_step_viewed',
    'onboarding_step_completed',
    'onboarding_completed',
    'onboarding_resumed',
    'onboarding_branch_selected',
    'insight_opened',
  };
  static const _values = <String, Set<String>>{
    'mode': {'discover', 'explore', 'build', 'prove', 'launch', 'graduate'},
    'branch': {'school', 'university', 'graduate'},
    'tone': {'neutral', 'positive', 'warning', 'maroon', 'teal', 'amber'},
    'phase': {'startup', 'render', 'runtime'},
    'screen': {
      'dashboard',
      'onboarding',
      'roadmap',
      'applications',
      'vault',
      'coach',
      'interview',
      'profile',
      'settings',
      'radar',
      'analyser',
    },
    'step': {
      'name',
      'branch',
      'school',
      'university',
      'year',
      'field',
      'skills',
      'experience',
      'projects',
      'goals',
      'review',
    },
  };

  /// Only named counts, flags and enumerated values may leave the device.
  static Map<String, Object?> _clean(Map<String, Object?> properties) {
    final out = <String, Object?>{};
    properties.forEach((key, value) {
      if (const {'count', 'step', 'actions_shown'}.contains(key) &&
          value is int &&
          value >= 0 &&
          value <= 10000) {
        out[key] = value;
      } else if (key == 'completed' && value is bool) {
        out[key] = value;
      } else if (value is String && (_values[key]?.contains(value) ?? false)) {
        out[key] = value;
      }
    });
    return out;
  }
}

/// Test-only access to the property filter, which is the guarantee that no
/// personal data reaches the events table.
@visibleForTesting
class AnalyticsTestAccess {
  const AnalyticsTestAccess._();

  static Map<String, Object?> clean(Map<String, Object?> properties) =>
      Analytics._clean(properties);
}

final analyticsProvider = Provider<Analytics>((ref) {
  final analytics = Analytics(ref.watch(supabaseProvider));
  ref.onDispose(analytics.dispose);
  return analytics;
});
