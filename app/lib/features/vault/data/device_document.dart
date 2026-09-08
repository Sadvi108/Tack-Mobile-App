import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/failure.dart';

/// Opens a private local copy through the phone's document chooser.
class DeviceDocument {
  const DeviceDocument._();
  static const channel = MethodChannel('com.tack.app/documents');

  static String fileName(String title, String mime) {
    final extension = switch (mime) {
      'application/pdf' => 'pdf',
      'application/msword' => 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'docx',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const Failure('That file type cannot be opened yet.'),
    };
    var base = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    base = base.replaceFirst(
      RegExp(r'\.(pdf|docx?|jpe?g|png|webp)$', caseSensitive: false),
      '',
    );
    if (base.isEmpty || base == '.' || base == '..') base = 'Document';
    if (base.length > 80) base = base.substring(0, 80);
    return '$base.$extension';
  }

  static Future<File> destination(
    String userId,
    String documentId,
    String name,
  ) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/tack_documents',
    );
    await root.create(recursive: true);
    // Temporary copies are not a second permanent document vault.
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File && (await item.lastModified()).isBefore(cutoff)) {
        await item.delete();
      }
    }
    final folder = Directory('${root.path}/$userId/$documentId');
    await folder.create(recursive: true);
    return File('${folder.path}/$name');
  }

  static Future<void> open(File file, String mime) async {
    try {
      await channel.invokeMethod<void>('open', {
        'path': file.path,
        'mimeType': mime,
      });
    } on PlatformException catch (error) {
      throw Failure(
        error.code == 'no_app'
            ? 'No app on this phone can open that file. Install a PDF or document reader, then try again.'
            : 'The file could not be opened. Try again.',
        cause: error,
      );
    } on MissingPluginException {
      throw const Failure(
        'Opening files needs the updated mobile app. Restart Tack after updating it.',
      );
    }
  }
}
