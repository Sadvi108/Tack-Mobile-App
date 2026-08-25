import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/vault/data/document_models.dart';

void main() {
  group('storage keys', () {
    // The storage policies read ownership straight off the path, so this shape
    // is a security boundary, not a naming convention.
    test('are exactly users/{userId}/{type}/{documentId}', () {
      final key = UploadRules.storageKey(
        userId: '11111111-2222-3333-4444-555555555555',
        type: DocumentType.cv,
        documentId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(key,
          'users/11111111-2222-3333-4444-555555555555/cv/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });

    test('the second segment is the owner, which is what the policy checks', () {
      const userId = '11111111-2222-3333-4444-555555555555';
      for (final type in DocumentType.values) {
        final parts = UploadRules.storageKey(
          userId: userId,
          type: type,
          documentId: 'doc',
        ).split('/');
        expect(parts.first, 'users');
        expect(parts[1], userId);
        expect(parts[2], type.name);
        expect(parts, hasLength(4));
      }
    });
  });

  group('what the vault accepts', () {
    test('a normal PDF is fine', () {
      expect(
        UploadRules.reject(mimeType: 'application/pdf', sizeBytes: 400 * 1024),
        isNull,
      );
    });

    test('a photo of a paper certificate is fine', () {
      // Many students have paper certificates and no scanner, so the camera
      // has to be a first-class option.
      expect(UploadRules.reject(mimeType: 'image/jpeg', sizeBytes: 2 * 1024 * 1024), isNull);
    });

    test('an oversized file says how big it is and what the limit is', () {
      final message = UploadRules.reject(
        mimeType: 'application/pdf',
        sizeBytes: 12 * 1024 * 1024,
      );
      expect(message, contains('12.0MB'));
      expect(message, contains('10MB'));
    });

    test('an unsupported type explains what is accepted instead', () {
      final message = UploadRules.reject(mimeType: 'application/zip', sizeBytes: 1024);
      expect(message, contains('PDFs'));
      expect(message, isNot(contains('application/zip')),
          reason: 'a MIME type means nothing to a student');
    });

    test('an unknown type is refused rather than assumed safe', () {
      expect(UploadRules.reject(mimeType: null, sizeBytes: 1024), isNotNull);
    });

    test('an empty file is refused', () {
      expect(UploadRules.reject(mimeType: 'application/pdf', sizeBytes: 0), isNotNull);
    });

    test('exactly at the limit is allowed', () {
      expect(
        UploadRules.reject(mimeType: 'application/pdf', sizeBytes: UploadRules.maxBytes),
        isNull,
      );
      expect(
        UploadRules.reject(mimeType: 'application/pdf', sizeBytes: UploadRules.maxBytes + 1),
        isNotNull,
      );
    });

    test('no message blames the student', () {
      final messages = [
        UploadRules.reject(mimeType: 'application/zip', sizeBytes: 1024),
        UploadRules.reject(mimeType: 'application/pdf', sizeBytes: 0),
        UploadRules.reject(mimeType: 'application/pdf', sizeBytes: 99 * 1024 * 1024),
      ].whereType<String>();

      for (final message in messages) {
        for (final banned in ['you must', 'invalid', 'error', 'failed', 'wrong']) {
          expect(message.toLowerCase(), isNot(contains(banned)),
              reason: '"$message" should not say "$banned"');
        }
      }
    });
  });
}
