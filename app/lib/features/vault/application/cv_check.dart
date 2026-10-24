import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/failure.dart';
import '../data/document_repository.dart';
import '../data/first_read_models.dart';
export '../data/document_models.dart';
export '../data/first_read_models.dart';
export '../data/document_repository.dart'
    show documentsProvider, documentRepositoryProvider;

final cvCheckProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(documentRepositoryProvider).checkResult(id),
    );

final firstReadProvider = FutureProvider.autoDispose.family<FirstRead?, String>(
  (ref, id) => ref.watch(documentRepositoryProvider).latestFirstRead(id),
);

/// Whether a first read is under way for one CV.
class FirstReadController extends Notifier<bool> {
  FirstReadController(this.documentId);

  final String documentId;

  @override
  bool build() => false;

  /// Returns a message to show when it could not finish, otherwise null.
  Future<String?> request() async {
    if (state) return null;
    state = true;
    try {
      await ref.read(documentRepositoryProvider).requestFirstRead(documentId);
      ref.invalidate(firstReadProvider(documentId));
      return null;
    } catch (e) {
      return Failure.from(e).message;
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

final firstReadRequestProvider =
    NotifierProvider.family<FirstReadController, bool, String>(
      FirstReadController.new,
    );
