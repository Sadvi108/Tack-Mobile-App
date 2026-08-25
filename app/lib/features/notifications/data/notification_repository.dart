import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';

class TackNotification {
  const TackNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// Where tapping it should take the student.
  String get route => switch (type) {
    'analysis_ready' => '/analyser',
    'cv_parsed' => '/vault',
    'deadline' => '/applications',
    'score_changed' => '/score',
    _ => '/home',
  };

  factory TackNotification.fromRow(Map<String, dynamic> row) =>
      TackNotification(
        id: row['id'] as String,
        type: (row['type'] as String?) ?? 'general',
        title: row['title'] as String,
        body: row['body'] as String?,
        createdAt:
            DateTime.tryParse('${row['created_at']}')?.toLocal() ??
            DateTime.now(),
        readAt: DateTime.tryParse('${row['read_at']}')?.toLocal(),
      );
}

class NotificationRepository {
  const NotificationRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<List<TackNotification>> all({int limit = 50}) async {
    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('user_id', _uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(TackNotification.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', _uid)
          .isFilter('read_at', null);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseProvider)),
);

final notificationsProvider = FutureProvider<List<TackNotification>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(notificationRepositoryProvider).all();
});

final unreadCountProvider = Provider<int>((ref) {
  final list =
      ref.watch(notificationsProvider).value ?? const <TackNotification>[];
  return list.where((n) => n.isUnread).length;
});
