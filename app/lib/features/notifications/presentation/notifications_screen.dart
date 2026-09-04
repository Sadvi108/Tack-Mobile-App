import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../data/notification_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);

    return TackScaffold(
      header: TackHeader(
        title: 'Updates',
        onBack: () => tackBack(context),
        trailing: unread == 0
            ? null
            : TackButton.ghost(
                'Mark all read',
                fullWidth: false,
                onPressed: () async {
                  await ref.read(notificationRepositoryProvider).markAllRead();
                  ref.invalidate(notificationsProvider);
                },
              ),
      ),
      body: notificationsAsync.when(
        loading: () => const Column(
          children: [
            TackSkeleton(height: 76, radius: 18),
            SizedBox(height: TackSpace.row),
            TackSkeleton(height: 76, radius: 18),
          ],
        ),
        error: (_, _) => TackErrorState(
          body:
              'Your updates did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const TackEmptyState(
              title: 'Nothing yet',
              body:
                  'When a CV finishes being read or a deadline gets close, it will show '
                  'up here.',
            );
          }

          return Column(
            children: [
              for (final notification in notifications) ...[
                TackCard(
                  compact: true,
                  onTap: () async {
                    await ref
                        .read(notificationRepositoryProvider)
                        .markRead(notification.id);
                    ref.invalidate(notificationsProvider);
                    if (context.mounted) context.go(notification.route);
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 12),
                        decoration: BoxDecoration(
                          color: notification.isUnread
                              ? TackColors.maroon
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notification.title,
                              style: TackText.rowTitle.copyWith(
                                fontWeight: notification.isUnread
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            if (notification.body != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                notification.body!,
                                style: TackText.bodyMuted,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              _ago(notification.createdAt),
                              style: TackText.monoLabelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: TackSpace.row),
              ],
              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }

  static String _ago(DateTime when) {
    final difference = DateTime.now().difference(when);
    if (difference.inMinutes < 1) return 'JUST NOW';
    if (difference.inMinutes < 60) return '${difference.inMinutes} MIN AGO';
    if (difference.inHours < 24) return '${difference.inHours} H AGO';
    if (difference.inDays == 1) return 'YESTERDAY';
    return '${difference.inDays} DAYS AGO';
  }
}
