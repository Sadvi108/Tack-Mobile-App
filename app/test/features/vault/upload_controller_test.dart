import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/features/vault/application/upload_controller.dart';
import 'package:tack/features/vault/data/document_models.dart';
import 'package:tack/features/vault/data/document_repository.dart';

/// Records what the controller asked for. The Supabase client it is handed is
/// never used — every method that would reach the network is overridden.
class _FakeRepository extends DocumentRepository {
  _FakeRepository({this.checkFails = false, this.hold})
    : super(SupabaseClient('http://localhost', 'test-key'));

  final bool checkFails;

  /// Lets a test hold the check open and look at the card while it runs.
  final Future<void>? hold;

  final List<String> checkRequests = [];
  final List<String> scoreRequests = [];

  @override
  Future<TackDocument> upload({
    required DocumentType type,
    required String title,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    onProgress?.call(1);
    return TackDocument(
      id: 'doc-1',
      type: type,
      title: title,
      storagePath: 'users/u/${type.name}/doc-1',
      // Every upload now lands ready. Reading a CV is a separate, free check
      // rather than something the file itself waits on.
      status: DocumentStatus.ready,
      createdAt: DateTime(2026),
    );
  }

  @override
  Future<void> requestCheck(String documentId) async {
    checkRequests.add(documentId);
    if (hold != null) await hold;
    if (checkFails) throw const Failure('no network');
  }

  /// The paid path. Uploading must never reach it.
  @override
  Future<void> requestScore(String documentId) async {
    scoreRequests.add(documentId);
  }
}

ProviderContainer _containerWith(_FakeRepository repository) {
  final container = ProviderContainer(
    overrides: [documentRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<bool> _upload(ProviderContainer container, DocumentType type) =>
    container
        .read(uploadControllerProvider.notifier)
        .upload(
          type: type,
          title: 'My CV',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'application/pdf',
        );

void main() {
  group('uploading a CV', () {
    test('asks for the check that costs no AI action', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.cv), isTrue);
      expect(repository.checkRequests, ['doc-1']);
    });

    test('never spends an AI action on its own', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _upload(container, DocumentType.cv);

      // Reading a CV with a model is something the student opts into from the
      // check screen. Uploading must not decide that for them.
      expect(repository.scoreRequests, isEmpty);
    });

    test('shows that reading is under way while it is', () async {
      final gate = Completer<void>();
      final repository = _FakeRepository(hold: gate.future);
      final container = _containerWith(repository);

      final pending = _upload(container, DocumentType.cv);
      await Future<void>.delayed(Duration.zero);

      final during = container.read(uploadControllerProvider);
      expect(during.parsing, isTrue);
      expect(during.failure, isNull);

      gate.complete();
      expect(await pending, isTrue);
    });

    test('and lets the card go once the check is saved', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _upload(container, DocumentType.cv);

      // The result is opened from the CV's menu, so the upload card has
      // nothing left to say and should not sit there spinning.
      final state = container.read(uploadControllerProvider);
      expect(state.parsing, isFalse);
      expect(state.failure, isNull);
    });
  });

  group('uploading anything else', () {
    test('does not ask for a check', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.certificate), isTrue);
      expect(repository.checkRequests, isEmpty);
    });

    test('finishes idle rather than parsing', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _upload(container, DocumentType.transcript);
      expect(container.read(uploadControllerProvider).parsing, isFalse);
    });
  });

  group('when the check cannot be started', () {
    test('the student is told the file is safe and what to do', () async {
      final repository = _FakeRepository(checkFails: true);
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.cv), isFalse);

      final message = container.read(uploadControllerProvider).failure?.message;
      expect(message, isNotNull);
      expect(message, contains('saved'));
      expect(message, contains('try again'));
    });

    test('no message blames the student', () async {
      final repository = _FakeRepository(checkFails: true);
      final container = _containerWith(repository);

      await _upload(container, DocumentType.cv);
      final message = container
          .read(uploadControllerProvider)
          .failure!
          .message
          .toLowerCase();
      for (final blame in ['you failed', 'invalid', 'error', 'you did']) {
        expect(message, isNot(contains(blame)));
      }
    });
  });
}
