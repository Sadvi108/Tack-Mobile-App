import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/document_repository.dart';
export '../data/document_models.dart';
export '../data/document_repository.dart'
    show documentsProvider, documentRepositoryProvider;

final cvCheckProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(documentRepositoryProvider).checkResult(id),
    );
