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
    if (userId == null) return;

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

    final batch = List<Map<String, Object?>>.from(_buffer);
    _buffer.clear();

    try {
      await _db.from('analytics_events').insert(batch);
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
    _appVersion ??= await _version();
    try {
      await _db.from('error_reports').insert({
        'user_id': _uid,
        'message': error.toString().split('\n').first,
        'stack': stack?.toString().split('\n').take(20).join('\n'),
        'context': _clean(context ?? const {}),
        'app_version': _appVersion,
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {
      // Deliberately silent.
    }
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

  /// Last line of defence. Anything long enough to be prose, or holding a
  /// key that names personal data, is dropped rather than trusted.
  static Map<String, Object?> _clean(Map<String, Object?> properties) {
    const banned = {
      'name',
      'full_name',
      'email',
      'phone',
      'address',
      'cv',
      'cv_text',
      'answer',
      'notes',
      'description',
      'text',
      'title',
      'summary',
      'query',
    };
    final out = <String, Object?>{};
    properties.forEach((key, value) {
      if (banned.contains(key.toLowerCase())) return;
      if (value is String && value.length > 40) return;
      if (value is String || value is num || value is bool) out[key] = value;
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
