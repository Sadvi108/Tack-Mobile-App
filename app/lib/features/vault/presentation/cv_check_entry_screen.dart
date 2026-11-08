import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/cv_check.dart';
import 'cv_check_screen.dart';

/// The free CV check, opened without naming a CV.
///
/// The Toolkit, Home and the coach all link here, because none of them knows
/// which CV to check. This picks it: the default CV if the check can read it,
/// otherwise the newest one it can. With nothing to check it says what to do,
/// rather than opening a check that cannot run.
class CvCheckEntryScreen extends ConsumerWidget {
  const CvCheckEntryScreen({super.key});

  /// The CV to check, or null when no CV is in a format the check reads.
  static TackDocument? pick(List<TackDocument> documents) {
    final checkable = documents
        .where(
          (d) =>
              d.type == DocumentType.cv &&
              UploadRules.supportsCvCheck(d.mimeType),
        )
        .toList();
    if (checkable.isEmpty) return null;
    for (final cv in checkable) {
      if (cv.isDefault) return cv;
    }
    checkable.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return checkable.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);

    Widget frame(Widget body) => TackScaffold(
      header: TackHeader(
        title: 'Free CV check',
        onBack: () => tackBack(context, fallback: Routes.vault),
      ),
      body: body,
    );

    return documents.when(
      loading: () => frame(
        const Column(
          children: [
            TackSkeleton(height: 76, radius: 18),
            SizedBox(height: TackSpace.row),
            TackSkeleton(height: 76, radius: 18),
          ],
        ),
      ),
      error: (_, _) => frame(
        TackErrorState(
          title: 'Your documents did not load',
          body: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(documentsProvider),
        ),
      ),
      data: (list) {
        final cv = pick(list);
        if (cv != null) return CvCheckScreen(documentId: cv.id);
        final hasUnreadableCv = list.any((d) => d.type == DocumentType.cv);
        return frame(
          TackEmptyState(
            title: hasUnreadableCv
                ? 'Add your CV as a PDF or Word file'
                : 'Add your CV to check it',
            body: hasUnreadableCv
                ? 'The free check reads PDF and Word files. Upload one of '
                      'those, or build one from your profile.'
                : 'Upload a PDF or Word file, or build one from your '
                      'profile. The check is free.',
            primaryLabel: 'Add my CV',
            onPrimary: () => context.go(Routes.vault),
            secondaryLabel: 'Build my CV',
            onSecondary: () => context.push(Routes.cvBuilder),
          ),
        );
      },
    );
  }
}
