import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../vault/data/document_models.dart';
import '../../vault/data/document_repository.dart';
import '../data/cv_pdf.dart';
import '../data/profile_document.dart';

/// Builds a CV out of what Tack already knows.
///
/// Tack has been able to score a CV since the beginning and never able to make
/// one, which left a student with no CV holding a number and no way to act on
/// it. This closes that.
///
/// Nothing here asks the student to type their history again. Every section is
/// already filled from their profile; the only decisions on this screen are
/// what to show and in what order.
class CvBuilderScreen extends ConsumerStatefulWidget {
  const CvBuilderScreen({super.key});

  @override
  ConsumerState<CvBuilderScreen> createState() => _CvBuilderScreenState();
}

class _CvBuilderScreenState extends ConsumerState<CvBuilderScreen> {
  CvLayout? _layout;
  bool _busy = false;

  Future<void> _persist(CvLayout next) async {
    setState(() => _layout = next);
    try {
      await ref.read(cvBuilderRepositoryProvider).saveLayout(next);
    } catch (e) {
      if (!mounted) return;
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }

  Future<Uint8List> _render(ProfileDocument document, CvLayout layout) =>
      CvPdf.build(document: document, layout: layout);

  Future<void> _preview(ProfileDocument document, CvLayout layout) async {
    final bytes = await _render(document, layout);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Your CV')),
          body: PdfPreview(
            build: (_) => bytes,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: 'cv.pdf',
          ),
        ),
      ),
    );
  }

  /// Saves it into the Vault, which is what closes the loop: `score-cv` picks
  /// up any CV that lands there, so building one immediately gets it scored
  /// and the student sees what to fix next.
  Future<void> _saveToVault(ProfileDocument document, CvLayout layout) async {
    setState(() => _busy = true);
    try {
      final bytes = await _render(document, layout);
      final name = document.identity.fullName ?? 'My';
      await ref
          .read(documentRepositoryProvider)
          .upload(
            type: DocumentType.cv,
            title: '$name CV — built in Tack',
            bytes: bytes,
            mimeType: 'application/pdf',
          );
      if (!mounted) return;
      setState(() => _busy = false);
      TackToast.show(
        context,
        message: 'Saved to your Vault. Tack is reading it now.',
        actionLabel: 'Open',
        onAction: () => context.go(Routes.vault),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(profileDocumentProvider);
    final stored = ref.watch(cvLayoutProvider);

    return document.when(
      loading: () => _shell(body: const TackSkeleton(height: 320, radius: 20)),
      error: (_, _) => _shell(
        body: TackErrorState(
          body:
              'Your CV could not be loaded. Check your connection and try '
              'again.',
          onRetry: () => ref.invalidate(profileDocumentProvider),
        ),
      ),
      data: (doc) {
        if (!doc.hasSubstance) return _shell(body: _NothingYet(doc: doc));

        final layout = _layout ?? stored.value ?? const CvLayout();

        return _shell(
          pinnedCta: TackButton(
            'Save to my Vault',
            loading: _busy,
            onPressed: () => _saveToVault(doc, layout),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Everything here is already on your profile. Choose what goes '
                'on the page and in what order.',
                style: TackText.bodyMuted,
              ),
              const SizedBox(height: TackSpace.lg),

              TackButton.secondary(
                'Preview the PDF',
                onPressed: () => _preview(doc, layout),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              Text('ON THE PAGE', style: TackText.monoLabelSmall),
              const SizedBox(height: TackSpace.sm),
              _Sections(layout: layout, doc: doc, onChanged: _persist),

              if (layout.hidden.isNotEmpty) ...[
                const SizedBox(height: TackSpace.stackLoose),
                Text('NOT SHOWN', style: TackText.monoLabelSmall),
                const SizedBox(height: TackSpace.sm),
                TackCard(
                  child: Column(
                    children: [
                      for (final section in layout.hidden) ...[
                        if (section != layout.hidden.first) const TackDivider(),
                        _HiddenRow(
                          section: section,
                          count: doc.countFor(section),
                          onAdd: () => _persist(
                            layout.withSections([...layout.sections, section]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }

  Widget _shell({required Widget body, Widget? pinnedCta}) => TackScaffold(
    header: TackHeader(
      title: 'Build your CV',
      onBack: () => tackBack(context, fallback: Routes.vault),
    ),
    pinnedCta: pinnedCta,
    body: body,
  );
}

/// The reorderable list of shown sections.
///
/// A section the student has no data for stays in the list rather than being
/// hidden automatically — it says "nothing yet", which is a prompt to go and
/// add something. Silently removing it would hide the gap.
class _Sections extends StatelessWidget {
  const _Sections({
    required this.layout,
    required this.doc,
    required this.onChanged,
  });

  final CvLayout layout;
  final ProfileDocument doc;
  final ValueChanged<CvLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        // onReorderItem, not onReorder: the newer callback already accounts
        // for the removed item, so the usual `to - 1` fudge is not needed and
        // applying it would move things one place short.
        onReorderItem: (from, to) {
          final next = [...layout.sections];
          next.insert(to, next.removeAt(from));
          onChanged(layout.withSections(next));
        },
        children: [
          for (final (index, section) in layout.sections.indexed)
            _SectionRow(
              key: ValueKey(section),
              index: index,
              section: section,
              count: doc.countFor(section),
              onRemove: () => onChanged(
                layout.withSections(
                  layout.sections.where((s) => s != section).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.index,
    required this.section,
    required this.count,
    required this.onRemove,
  });

  final int index;
  final CvSection section;
  final int count;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(right: TackSpace.sm),
            child: SizedBox(
              width: 32,
              height: TackSpace.tapTarget,
              child: Center(
                child: TackIcon(
                  TackIcons.dragHandle,
                  size: 18,
                  color: TackColors.muted,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(section.heading, style: TackText.rowTitle),
              Text(
                count == 0
                    ? 'Nothing yet'
                    : '$count ${count == 1 ? 'entry' : 'entries'}',
                style: TackText.meta,
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onRemove,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: TackSpace.tapTarget,
            height: TackSpace.tapTarget,
            child: Center(
              child: TackIcon(
                TackIcons.close,
                size: 18,
                color: TackColors.muted,
                semanticLabel: 'Remove ${section.heading}',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _HiddenRow extends StatelessWidget {
  const _HiddenRow({
    required this.section,
    required this.count,
    required this.onAdd,
  });

  final CvSection section;
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => TackTapRow(
    onTap: onAdd,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(section.heading, style: TackText.rowTitle),
              Text(
                count == 0 ? 'Nothing yet' : '$count available',
                style: TackText.meta,
              ),
            ],
          ),
        ),
        Text('Add', style: TackText.buttonSmall),
      ],
    ),
  );
}

/// What a student sees before they have anything worth printing.
///
/// Handing somebody a PDF containing only their own name is worse than telling
/// them what is missing, so this names the two or three things that would make
/// the biggest difference and sends them to the right screen.
class _NothingYet extends StatelessWidget {
  const _NothingYet({required this.doc});

  final ProfileDocument doc;

  @override
  Widget build(BuildContext context) {
    final missing = doc.whatIsMissing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Not quite yet', style: TackText.cardTitle),
        const SizedBox(height: TackSpace.sm),
        Text(
          'Tack builds your CV from your profile, and there is not enough on '
          'it to make one worth sending.',
          style: TackText.bodyMuted,
        ),
        const SizedBox(height: TackSpace.lg),
        TackCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ADD THESE FIRST', style: TackText.monoLabelSmall),
              const SizedBox(height: TackSpace.md),
              for (final item in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: TackSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: TackIcon(
                          TackIcons.plus,
                          size: 16,
                          color: TackColors.maroonText,
                        ),
                      ),
                      const SizedBox(width: TackSpace.sm),
                      Expanded(child: Text(item, style: TackText.body)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: TackSpace.lg),
        TackButton(
          'Go to your profile',
          onPressed: () => context.go(Routes.profile),
        ),
      ],
    );
  }
}
