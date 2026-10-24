import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/offline/sync.dart';
import '../data/checklist_models.dart';
import '../data/checklist_repository.dart';

export '../data/checklist_models.dart';
export '../data/checklist_repository.dart';

final checklistProvider = FutureProvider.autoDispose.family<Checklist, String>((
  ref,
  id,
) {
  // An attached CV or a status move is queued offline first; read again once
  // it has reached the server, or the item it cleared lingers.
  ref.watch(syncRevisionProvider);
  return ref.watch(checklistRepositoryProvider).checklist(id);
});

final prepBriefProvider = FutureProvider.autoDispose.family<PrepBrief?, String>(
  (ref, id) => ref.watch(checklistRepositoryProvider).latestBrief(id),
);

/// Whether a prep brief is being written for one application.
class PrepRequestController extends Notifier<bool> {
  PrepRequestController(this.applicationId);

  final String applicationId;

  @override
  bool build() => false;

  /// Returns a message to show when it could not finish, otherwise null.
  Future<String?> request() async {
    if (state) return null;
    state = true;
    try {
      await ref.read(checklistRepositoryProvider).requestBrief(applicationId);
      ref
        ..invalidate(prepBriefProvider(applicationId))
        ..invalidate(checklistProvider(applicationId));
      return null;
    } catch (e) {
      return Failure.from(e).message;
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

final prepRequestProvider =
    NotifierProvider.family<PrepRequestController, bool, String>(
      PrepRequestController.new,
    );
