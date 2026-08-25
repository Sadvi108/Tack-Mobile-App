import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../application/upload_controller.dart';
import '../data/document_models.dart';
import '../data/document_repository.dart';

/// The document vault.
///
/// The empty state does the heavy lifting: it names the three things worth
/// uploading, says plainly who can see them, and offers the phone camera as an
/// equal option — many students have paper certificates and no scanner.
class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentsAsync = ref.watch(documentsProvider);
    final upload = ref.watch(uploadControllerProvider);

    return TackScaffold(
      header: TackHeader(title: 'Your documents', onBack: () => context.pop()),
      pinnedCta: upload.busy
          ? null
          : TackButton('Add a file', onPressed: () => _pickAndUpload(context, ref)),
      body: documentsAsync.when(
        loading: () => const Column(
          children: [
            TackSkeleton(height: 88, radius: 18),
            SizedBox(height: TackSpace.stack),
            TackSkeleton(height: 88, radius: 18),
          ],
        ),
        error: (_, _) => TackErrorState(
          body: 'Your documents did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(documentsProvider),
        ),
        data: (documents) {
          final cvs = documents.where((d) => d.type == DocumentType.cv).toList();
          final others = documents.where((d) => d.type != DocumentType.cv).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (upload.busy || upload.failure != null) ...[
                _UploadCard(state: upload),
                const SizedBox(height: TackSpace.stackLoose),
              ],

              if (documents.isEmpty)
                _EmptyVault(
                  onPickFile: () => _pickAndUpload(context, ref),
                  onUseCamera: () => _cameraUpload(context, ref),
                )
              else ...[
                if (cvs.isNotEmpty) ...[
                  Text('Your CV', style: TackText.sectionHeader),
                  const SizedBox(height: TackSpace.md),
                  for (final cv in cvs) ...[
                    _DocumentRow(
                      document: cv,
                      onMenu: () => _menu(context, ref, cv),
                    ),
                    const SizedBox(height: TackSpace.row),
                  ],
                  const SizedBox(height: TackSpace.lg),
                ],
                if (others.isNotEmpty) ...[
                  Text('Everything else', style: TackText.sectionHeader),
                  const SizedBox(height: TackSpace.md),
                  for (final document in others) ...[
                    _DocumentRow(
                      document: document,
                      onMenu: () => _menu(context, ref, document),
                    ),
                    const SizedBox(height: TackSpace.row),
                  ],
                ],
                const SizedBox(height: TackSpace.lg),
                _PrivacyNote(),
              ],

              const SizedBox(height: TackSpace.xl),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final choice = await showTackSheet<String>(
      context: context,
      title: 'Add a file',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetOption(
            icon: TackIcons.file,
            title: 'Choose a file',
            body: 'A PDF or Word document already on your phone',
            onTap: () => Navigator.of(context).pop('file'),
          ),
          const TackDivider(indent: TackSpace.screen),
          _SheetOption(
            icon: TackIcons.camera,
            title: 'Take a photo',
            body: 'For paper certificates and printed transcripts',
            onTap: () => Navigator.of(context).pop('camera'),
          ),
          const SizedBox(height: TackSpace.lg),
        ],
      ),
    );

    if (!context.mounted) return;
    if (choice == 'camera') return _cameraUpload(context, ref);
    if (choice != 'file') return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || !context.mounted) return;

    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: 'That file could not be read. Try another one.',
          kind: TackToastKind.error,
        );
      }
      return;
    }

    if (!context.mounted) return;
    await _confirmAndUpload(
      context,
      ref,
      bytes: bytes,
      suggestedTitle: file.name,
      mimeType: lookupMimeType(file.name, headerBytes: bytes.take(64).toList()) ??
          'application/octet-stream',
    );
  }

  Future<void> _cameraUpload(BuildContext context, WidgetRef ref) async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 2000,
    );
    if (photo == null || !context.mounted) return;

    final bytes = await photo.readAsBytes();
    if (!context.mounted) return;

    await _confirmAndUpload(
      context,
      ref,
      bytes: bytes,
      suggestedTitle: 'Photo ${DateTime.now().day}/${DateTime.now().month}',
      mimeType: photo.mimeType ?? lookupMimeType(photo.path) ?? 'image/jpeg',
    );
  }

  Future<void> _confirmAndUpload(
    BuildContext context,
    WidgetRef ref, {
    required Uint8List bytes,
    required String suggestedTitle,
    required String mimeType,
  }) async {
    final rejection = UploadRules.reject(mimeType: mimeType, sizeBytes: bytes.length);
    if (rejection != null) {
      TackToast.show(context, message: rejection, kind: TackToastKind.error);
      return;
    }

    final controller = TextEditingController(text: suggestedTitle);
    var type = DocumentType.cv;

    final confirmed = await showTackSheet<bool>(
      context: context,
      title: 'What is this?',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            TackSpace.screen,
            0,
            TackSpace.screen,
            MediaQuery.viewInsetsOf(sheetContext).bottom + TackSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: TackSpace.sm,
                runSpacing: TackSpace.sm,
                children: [
                  for (final option in DocumentType.values)
                    TackChip(
                      option.label,
                      selected: type == option,
                      onTap: () => setSheetState(() => type = option),
                    ),
                ],
              ),
              const SizedBox(height: TackSpace.lg),
              TackTextField(label: 'Name it', controller: controller),
              const SizedBox(height: TackSpace.xl),
              TackButton('Upload', onPressed: () => Navigator.of(sheetContext).pop(true)),
            ],
          ),
        ),
      ),
    );

    final title = controller.text.trim();
    controller.dispose();
    if (confirmed != true || title.isEmpty) return;

    final ok = await ref.read(uploadControllerProvider.notifier).upload(
          type: type,
          title: title,
          bytes: bytes,
          mimeType: mimeType,
        );

    if (!context.mounted) return;
    if (ok) {
      TackToast.show(
        context,
        message: type == DocumentType.cv
            ? 'Uploaded. Reading your CV now — you can leave this screen.'
            : 'Uploaded.',
      );
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, TackDocument document) async {
    final action = await showTackSheet<String>(
      context: context,
      title: document.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (document.type == DocumentType.cv && !document.isDefault)
            _SheetOption(
              icon: TackIcons.star,
              title: 'Make this my default CV',
              body: 'It gets attached to new applications',
              onTap: () => Navigator.of(context).pop('default'),
            ),
          _SheetOption(
            icon: TackIcons.download,
            title: 'Open it',
            body: 'Opens with a private link that expires in five minutes',
            onTap: () => Navigator.of(context).pop('open'),
          ),
          _SheetOption(
            icon: TackIcons.edit,
            title: 'Rename it',
            body: 'Only you see this name',
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          _SheetOption(
            icon: TackIcons.trash,
            title: 'Delete it',
            body: 'Recoverable for 30 days',
            danger: true,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
          const SizedBox(height: TackSpace.lg),
        ],
      ),
    );

    if (action == null || !context.mounted) return;
    final repository = ref.read(documentRepositoryProvider);

    try {
      switch (action) {
        case 'default':
          await repository.makeDefault(document.id);
          ref.invalidate(documentsProvider);
          if (context.mounted) {
            TackToast.show(context, message: '${document.title} is now your default CV.');
          }
        case 'open':
          final url = await repository.signedUrl(document.id);
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        case 'rename':
          if (!context.mounted) return;
          await _rename(context, ref, document);
        case 'delete':
          if (!context.mounted) return;
          final confirmed = await confirmTackAction(
            context,
            title: 'Delete ${document.title}?',
            body: 'It stays recoverable for 30 days, then it is gone for good.',
            confirmLabel: 'Delete it',
          );
          if (!confirmed) return;
          await repository.remove(document.id);
          ref.invalidate(documentsProvider);
          if (context.mounted) TackToast.show(context, message: 'Deleted.');
      }
    } catch (e) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: Failure.from(e).message,
          kind: TackToastKind.error,
        );
      }
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, TackDocument document) async {
    final controller = TextEditingController(text: document.title);
    final saved = await showTackSheet<bool>(
      context: context,
      title: 'Rename',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TackTextField(controller: controller, autofocus: true),
            const SizedBox(height: TackSpace.lg),
            Builder(
              builder: (sheetContext) =>
                  TackButton('Save', onPressed: () => Navigator.of(sheetContext).pop(true)),
            ),
          ],
        ),
      ),
    );

    final title = controller.text.trim();
    controller.dispose();
    if (saved != true || title.isEmpty) return;

    await ref.read(documentRepositoryProvider).rename(document.id, title);
    ref.invalidate(documentsProvider);
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.onPickFile, required this.onUseCamera});

  final VoidCallback onPickFile;
  final VoidCallback onUseCamera;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Three things worth keeping here', style: TackText.sectionHeader),
              const SizedBox(height: TackSpace.md),
              const _WorthKeeping(
                title: 'Your CV',
                body: 'Tack reads it and fills in your profile for you.',
              ),
              const _WorthKeeping(
                title: 'Certificates',
                body: 'Course certificates, training, anything you earned.',
              ),
              const _WorthKeeping(
                title: 'Transcripts',
                body: 'So your results are to hand when a form asks.',
              ),
              const SizedBox(height: TackSpace.lg),
              TackButton('Choose a file', onPressed: onPickFile),
              const SizedBox(height: TackSpace.row),
              // The camera is an equal option, not a fallback.
              TackButton.secondary('Take a photo instead', onPressed: onUseCamera),
            ],
          ),
        ),
        const SizedBox(height: TackSpace.stackLoose),
        _PrivacyNote(),
      ],
    );
  }
}

class _WorthKeeping extends StatelessWidget {
  const _WorthKeeping({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7, right: 12),
            decoration: const BoxDecoration(color: TackColors.amber, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TackText.rowTitle),
                const SizedBox(height: 2),
                Text(body, style: TackText.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: TackColors.tealTint,
      compact: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TackIcon(TackIcons.shield, size: 20, color: TackColors.tealText),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Text(
              'Only you can open these files. Tack does not show them to employers, and '
              'nobody else on Tack can see them.',
              style: TackText.bodyMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends ConsumerWidget {
  const _UploadCard({required this.state});

  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.failure != null) {
      return TackErrorState(
        title: 'That did not upload',
        body: state.failure!.message,
        onRetry: () => ref.read(uploadControllerProvider.notifier).dismiss(),
      );
    }

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.parsing ? 'Reading your CV' : 'Uploading ${state.fileName ?? ''}',
            style: TackText.cardTitle,
          ),
          const SizedBox(height: TackSpace.md),
          if (state.parsing)
            const LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: TackColors.line,
              color: TackColors.teal,
            )
          else
            TackProgressBar(value: state.progress, height: 6),
          const SizedBox(height: TackSpace.sm),
          Text(
            state.parsing
                ? 'This takes about a minute. You can leave this screen — we will tell you '
                    'when it is done.'
                : '${(state.progress * 100).round()}% sent',
            style: TackText.bodyMuted,
          ),
          if (!state.parsing) ...[
            const SizedBox(height: TackSpace.md),
            TackButton.ghost(
              'Cancel',
              fullWidth: false,
              onPressed: () => ref.read(uploadControllerProvider.notifier).cancel(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? TackColors.danger : TackColors.ink;
    return TackTapRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: TackSpace.screen, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TackIcon(icon, size: 21, color: colour),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TackText.rowTitle.copyWith(color: colour)),
                const SizedBox(height: 2),
                Text(body, style: TackText.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.onMenu});

  final TackDocument document;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      compact: true,
      onTap: onMenu,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: TackColors.maroonTint,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const TackIcon(TackIcons.file, size: 20, color: TackColors.maroon),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        document.title,
                        style: TackText.rowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (document.isDefault) ...[
                      const SizedBox(width: TackSpace.sm),
                      const TackPill('Default'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    document.type.label,
                    if (document.sizeLabel.isNotEmpty) document.sizeLabel,
                    if (document.isProcessing) 'being read',
                    if (document.status == DocumentStatus.failed) 'did not upload',
                  ].join(' · '),
                  style: TackText.meta,
                ),
              ],
            ),
          ),
          const TackIcon(TackIcons.more, size: 20, color: TackColors.muted),
        ],
      ),
    );
  }
}
