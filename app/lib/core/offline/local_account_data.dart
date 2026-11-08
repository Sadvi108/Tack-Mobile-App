import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Everything this phone keeps for one account, and the way to erase it.
///
/// Two places hold an account's data on the device: its own drift database
/// (`tack_local_<uid>.sqlite` in the documents directory, which is where
/// drift_flutter puts it, with its `-wal`, `-shm` and `-journal` files), and
/// the temporary copies of documents opened on this phone
/// (`tack_documents/<uid>/` in the temporary directory). Deleting an account
/// on the server leaves both behind unless they are erased here.
class LocalAccountData {
  const LocalAccountData({required this.documents, required this.temporary});

  final Future<Directory> Function() documents;
  final Future<Directory> Function() temporary;

  /// A user id is a UUID. Anything else could walk out of the folder, so it
  /// erases nothing.
  static final _id = RegExp(r'^[A-Za-z0-9-]+$');

  /// Erases [uid]'s copy. Missing files are fine; other accounts are never
  /// touched.
  Future<void> erase(String uid) async {
    if (!_id.hasMatch(uid)) return;

    final docs = await documents();
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('${docs.path}/tack_local_$uid.sqlite$suffix');
      if (await file.exists()) await file.delete();
    }

    final opened = Directory('${(await temporary()).path}/tack_documents/$uid');
    if (await opened.exists()) await opened.delete(recursive: true);
  }
}

final localAccountDataProvider = Provider<LocalAccountData>(
  (ref) => const LocalAccountData(
    documents: getApplicationDocumentsDirectory,
    temporary: getTemporaryDirectory,
  ),
);
