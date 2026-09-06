import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problems = ref.watch(syncProblemsProvider).value ?? [];
    return TackScaffold(
      header: TackHeader(
        title: 'Saved changes',
        onBack: () => tackBack(context, fallback: Routes.settings),
      ),
      pinnedCta: TackButton(
        'Try syncing',
        onPressed: () => ref.read(syncServiceProvider).flush(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your changes stay on this phone until they are sent.',
            style: TackText.body,
          ),
          for (final item in problems) ...[
            const SizedBox(height: TackSpace.lg),
            TackCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.lastError == 'sync_conflict'
                        ? 'This application changed on another device'
                        : 'A change is waiting for a connection',
                    style: TackText.cardTitle,
                  ),
                  if (item.lastError == 'sync_conflict')
                    FutureBuilder<Map<String, dynamic>>(
                      future: ref
                          .read(syncServiceProvider)
                          .currentApplication(item.targetId),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Text(
                            'Connect to review both versions.',
                            style: TackText.body,
                          );
                        }
                        final remote = snapshot.data!;
                        final local = (jsonDecode(item.payload) as Map)
                            .cast<String, dynamic>();
                        const labels = {
                          'notes': 'Notes',
                          'status': 'Status',
                          'next_action': 'Next action',
                          'next_action_date': 'Next date',
                          'cv_document_id': 'CV version',
                          'applied_at': 'Application date',
                        };
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final key in labels.keys.where(
                              local.containsKey,
                            )) ...[
                              const SizedBox(height: TackSpace.md),
                              Text(
                                '${labels[key]} on this phone: ${local[key] ?? "Cleared"}',
                                style: TackText.body,
                              ),
                              Text(
                                '${labels[key]} on the other device: ${remote[key] ?? "Cleared"}',
                                style: TackText.bodyMuted,
                              ),
                            ],
                            const SizedBox(height: TackSpace.md),
                            TackButton.secondary(
                              'Keep this phone’s change',
                              onPressed: () => ref
                                  .read(syncServiceProvider)
                                  .resolveConflict(
                                    item,
                                    keepLocal: true,
                                    expectedVersion:
                                        remote['updated_at'] as String?,
                                  ),
                            ),
                            TackButton.ghost(
                              'Keep the other version',
                              onPressed: () => ref
                                  .read(syncServiceProvider)
                                  .resolveConflict(item, keepLocal: false),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
