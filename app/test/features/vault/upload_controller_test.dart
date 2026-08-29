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
  _FakeRepository({this.scoreFails = false})
    : super(SupabaseClient('http://localhost', 'test-key'));

  final bool scoreFails;
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
      // The repository puts a CV into processing and everything else into
      // ready, which is the branch the controller reads.
      status: type == DocumentType.cv
          ? DocumentStatus.processing
          : DocumentStatus.ready,
      createdAt: DateTime(2026),
    );
  }

  @override
  Future<void> requestScore(String documentId) async {
    scoreRequests.add(documentId);
    if (scoreFails) throw const Failure('no network');
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
    container.read(uploadControllerProvider.notifier).upload(
      type: type,
      title: 'My CV',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'application/pdf',
    );

void main() {
  group('uploading a CV', () {
    test('asks the server to read and score it', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.cv), isTrue);
      expect(repository.scoreRequests, ['doc-1']);
    });

    test('leaves the card showing that reading is under way', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _upload(container, DocumentType.cv);
      final state = container.read(uploadControllerProvider);
      expect(state.parsing, isTrue);
      expect(state.failure, isNull);
    });
  });

  group('uploading anything else', () {
    test('does not ask for a score', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.certificate), isTrue);
      expect(repository.scoreRequests, isEmpty);
    });

    test('finishes idle rather than parsing', () async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _upload(container, DocumentType.transcript);
      expect(container.read(uploadControllerProvider).parsing, isFalse);
    });
  });

  group('when scoring cannot be started', () {
    test('the student is told the file is safe and what to do', () async {
      final repository = _FakeRepository(scoreFails: true);
      final container = _containerWith(repository);

      expect(await _upload(container, DocumentType.cv), isFalse);

      final message = container.read(uploadControllerProvider).failure?.message;
      expect(message, isNotNull);
      expect(message, contains('saved'));
      expect(message, contains('try again'));
    });

    test('no message blames the student', () async {
      final repository = _FakeRepository(scoreFails: true);
      final container = _containerWith(repository);

      await _upload(container, DocumentType.cv);
      final message =
          container.read(uploadControllerProvider).failure!.message.toLowerCase();
      for (final blame in ['you failed', 'invalid', 'error', 'you did']) {
        expect(message, isNot(contains(blame)));
      }
    });
  });
}
