import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/cv_check.dart';

class CvCheckScreen extends ConsumerWidget {
  const CvCheckScreen({super.key, required this.documentId});
  final String documentId;

  Future<void> _readSkills(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(documentRepositoryProvider).requestScore(documentId);
      ref.invalidate(documentsProvider);
      if (context.mounted) {
        TackToast.show(
          context,
          message: 'Saved. Your CV score will appear when reading finishes.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: Failure.from(error).message,
          kind: TackToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(cvCheckProvider(documentId));
    return TackScaffold(
      header: TackHeader(
        title: 'Free CV check',
        onBack: () => tackBack(context, fallback: Routes.vault),
      ),
      pinnedCta: check.hasValue
          ? TackButton.secondary(
              'Read skills with AI',
              onPressed: () => _readSkills(context, ref),
            )
          : null,
      body: check.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your check is saved', style: TackText.sectionHeader),
            const SizedBox(height: TackSpace.md),
            Text(
              'Reading your CV. You can leave and open this check from your vault later. This uses no AI action.',
              style: TackText.body,
            ),
          ],
        ),
        error: (error, _) => TackErrorState(
          title: 'The check needs another try',
          body: Failure.from(error).message,
          onRetry: () => ref.invalidate(cvCheckProvider(documentId)),
        ),
        data: (result) {
          final findings = (result['findings'] as List? ?? const [])
              .whereType<Map>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Small changes to strengthen your CV',
                style: TackText.sectionHeader,
              ),
              const SizedBox(height: TackSpace.md),
              Text(
                'This check uses rules and costs no AI action.',
                style: TackText.bodyMuted,
              ),
              for (final finding in findings) ...[
                const SizedBox(height: TackSpace.lg),
                TackCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finding['title'] is String
                            ? finding['title'] as String
                            : 'Review this part',
                        style: TackText.cardTitle,
                      ),
                      const SizedBox(height: TackSpace.sm),
                      Text(
                        finding['detail'] is String
                            ? finding['detail'] as String
                            : '',
                        style: TackText.body,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: TackSpace.xl),
              Text(
                'Optional AI reading extracts skills from your CV. It uses one daily action when the file has not been read before. Your score is calculated by rules.',
                style: TackText.bodyMuted,
              ),
            ],
          );
        },
      ),
    );
  }
}
