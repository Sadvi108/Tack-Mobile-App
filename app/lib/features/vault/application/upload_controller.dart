import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../data/document_models.dart';
import '../data/document_repository.dart';

/// What the upload card is showing right now.
class UploadState {
  const UploadState({
    this.fileName,
    this.progress = 0,
    this.transferring = false,
    this.parsing = false,
    this.failure,
    this.cancelled = false,
  });

  final String? fileName;
  final double progress;

  /// Bytes are moving. The bar is determinate.
  final bool transferring;

  /// The file is up and a CV is being read. The bar is indeterminate and the
  /// student can leave the screen.
  final bool parsing;

  final Failure? failure;
  final bool cancelled;

  bool get busy => transferring || parsing;

  static const idle = UploadState();
}

class UploadController extends Notifier<UploadState> {
  bool _cancelRequested = false;

  @override
  UploadState build() => UploadState.idle;

  void cancel() {
    _cancelRequested = true;
    state = const UploadState(cancelled: true);
  }

  void dismiss() {
    _cancelRequested = false;
    state = UploadState.idle;
  }

  Future<bool> upload({
    required DocumentType type,
    required String title,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    _cancelRequested = false;
    state = UploadState(fileName: title, transferring: true);

    try {
      final document = await ref
          .read(documentRepositoryProvider)
          .upload(
            type: type,
            title: title,
            bytes: bytes,
            mimeType: mimeType,
            onProgress: (p) {
              if (state.transferring) {
                state = UploadState(
                  fileName: title,
                  progress: p,
                  transferring: true,
                );
              }
            },
            isCancelled: () async => _cancelRequested,
          );

      // A CV keeps going in the background; everything else is done.
      state = document.isProcessing
          ? UploadState(fileName: title, progress: 1, parsing: true)
          : UploadState.idle;

      ref.invalidate(documentsProvider);
      return true;
    } catch (e) {
      final failure = Failure.from(e);
      state = _cancelRequested
          ? const UploadState(cancelled: true)
          : UploadState(fileName: title, failure: failure);
      ref.invalidate(documentsProvider);
      return false;
    }
  }
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);
