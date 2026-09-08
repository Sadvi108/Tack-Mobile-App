import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/features/vault/data/device_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceDocument.channel, null),
  );
  test(
    'download names keep a correct reader extension and cannot escape the folder',
    () {
      expect(
        DeviceDocument.fileName('../resume.PDF', 'application/pdf'),
        '.._resume.pdf',
      );
      expect(
        DeviceDocument.fileName(
          'CV.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        'CV.docx',
      );
      expect(
        DeviceDocument.fileName('বাংলা জীবনবৃত্তান্ত', 'application/pdf'),
        'বাংলা জীবনবৃত্তান্ত.pdf',
      );
      expect(
        () => DeviceDocument.fileName('file', 'text/html'),
        throwsA(isA<Failure>()),
      );
    },
  );
  test(
    'the native chooser receives a local file and MIME type, without a signed URL',
    () async {
      MethodCall? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceDocument.channel, (call) async {
            sent = call;
            return null;
          });
      await DeviceDocument.open(
        File('/private/cache/tack_documents/u/d/CV.pdf'),
        'application/pdf',
      );
      expect(sent?.method, 'open');
      expect(sent?.arguments, {
        'path': '/private/cache/tack_documents/u/d/CV.pdf',
        'mimeType': 'application/pdf',
      });
    },
  );
  test('a phone without a reader gets an actionable error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceDocument.channel, (call) async {
          throw PlatformException(code: 'no_app');
        });
    await expectLater(
      DeviceDocument.open(File('/cache/CV.pdf'), 'application/pdf'),
      throwsA(
        isA<Failure>().having(
          (f) => f.message,
          'message',
          contains('Install a PDF'),
        ),
      ),
    );
  });
}
