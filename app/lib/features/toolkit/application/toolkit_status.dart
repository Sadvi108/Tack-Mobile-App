import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../interview/application/practice.dart';
import '../../vault/application/cv_check.dart';

// What the hub's screen reads from other features, through this layer only.
export '../../interview/application/practice.dart' show dueQuestionsProvider;
export '../../profile/application/profile.dart' show modeProvider, YearMode;

/// What the hub knows about the student's documents and practice.
///
/// Every field is null until its data has loaded, and stays null if it fails:
/// a card that depends on it waits, the rest of the hub does not.
class ToolkitStatus {
  const ToolkitStatus({
    this.documentCount,
    this.cvCount,
    this.hasCheckableCv,
    this.dueCount,
  });

  final int? documentCount;
  final int? cvCount;

  /// A CV in a format the free check reads (PDF or Word).
  final bool? hasCheckableCv;

  /// Practised answers due to try again.
  final int? dueCount;

  static ToolkitStatus from({List<TackDocument>? documents, int? dueCount}) {
    final cvs = documents?.where((d) => d.type == DocumentType.cv).toList();
    return ToolkitStatus(
      documentCount: documents?.length,
      cvCount: cvs?.length,
      hasCheckableCv: cvs?.any(
        (cv) => UploadRules.supportsCvCheck(cv.mimeType),
      ),
      dueCount: dueCount,
    );
  }
}

/// The student's documents, as the hub reads and refreshes them. The same
/// provider as the documents list, so a refresh here refreshes both.
final toolkitDocumentsProvider = documentsProvider;

/// Combines the documents and what is due. Never fails as a whole: a failed
/// read leaves its fields null.
final toolkitStatusProvider = Provider.autoDispose<ToolkitStatus>((ref) {
  final documents = ref.watch(documentsProvider);
  final due = ref.watch(dueQuestionsProvider);
  return ToolkitStatus.from(
    documents: documents.hasError ? null : documents.value,
    dueCount: due.hasError ? null : due.value?.length,
  );
});
