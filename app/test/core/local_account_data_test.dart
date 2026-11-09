import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_account_data.dart';

/// Deleting an account removed everything on the server and left this phone
/// holding a copy: the account's outbox and cached rows in its own database,
/// and any document opened in the last day. Erasing takes exactly that
/// account's copy, and nobody else's.
void main() {
  late Directory documents;
  late Directory temporary;
  late LocalAccountData data;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('tack_docs_');
    temporary = Directory.systemTemp.createTempSync('tack_tmp_');
    data = LocalAccountData(
      documents: () async => documents,
      temporary: () async => temporary,
    );
  });

  tearDown(() {
    documents.deleteSync(recursive: true);
    temporary.deleteSync(recursive: true);
  });

  const suffixes = ['', '-wal', '-shm', '-journal'];

  void seed(String uid) {
    for (final suffix in suffixes) {
      File('${documents.path}/tack_local_$uid.sqlite$suffix')
        ..createSync()
        ..writeAsStringSync('rows');
    }
    File('${temporary.path}/tack_documents/$uid/doc-1/CV.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('bytes');
  }

  test('erases one account and leaves another alone', () async {
    seed('user-a');
    seed('user-b');

    await data.erase('user-a');

    for (final suffix in suffixes) {
      expect(
        File('${documents.path}/tack_local_user-a.sqlite$suffix').existsSync(),
        isFalse,
        reason: 'user-a$suffix',
      );
      expect(
        File('${documents.path}/tack_local_user-b.sqlite$suffix').existsSync(),
        isTrue,
        reason: 'user-b$suffix',
      );
    }
    expect(
      Directory('${temporary.path}/tack_documents/user-a').existsSync(),
      isFalse,
    );
    expect(
      File('${temporary.path}/tack_documents/user-b/doc-1/CV.pdf').existsSync(),
      isTrue,
    );
  });

  test('nothing to erase is not an error', () async {
    await data.erase('never-signed-in-here');
  });

  test('an id that is not an id erases nothing', () async {
    seed('user-b');
    await data.erase('../tack_documents');
    await data.erase('');
    expect(
      File('${documents.path}/tack_local_user-b.sqlite').existsSync(),
      isTrue,
    );
    expect(Directory('${temporary.path}/tack_documents').existsSync(), isTrue);
  });
}
