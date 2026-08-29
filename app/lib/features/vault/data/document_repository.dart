import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import 'document_models.dart';

/// Uploads the bytes and reports how far along it is.
///
/// Injectable so the upload flow can be tested without a network: the real
/// implementation streams a PUT to a signed URL, which is the only way to get
/// a real byte count out of the storage API.
typedef UploadTransport =
    Future<void> Function({
      required Uri url,
      required Uint8List bytes,
      required String contentType,
      required void Function(int sent, int total) onProgress,
      required Future<bool> Function() isCancelled,
    });

Future<void> streamingUpload({
  required Uri url,
  required Uint8List bytes,
  required String contentType,
  required void Function(int sent, int total) onProgress,
  required Future<bool> Function() isCancelled,
}) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(url);
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.contentLength = bytes.length;

    // Chunked so progress is real rather than a two-step 0% then 100%.
    const chunkSize = 64 * 1024;
    var sent = 0;
    while (sent < bytes.length) {
      if (await isCancelled()) {
        request.abort();
        throw const Failure('Upload cancelled.');
      }
      final end = (sent + chunkSize).clamp(0, bytes.length);
      request.add(bytes.sublist(sent, end));
      await request.flush();
      sent = end;
      onProgress(sent, bytes.length);
    }

    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode >= 400) {
      throw Failure(
        'That file did not upload. Check your connection and try again.',
        code: '${response.statusCode}',
      );
    }
  } finally {
    client.close(force: true);
  }
}

class DocumentRepository {
  const DocumentRepository(this._db, {this.transport = streamingUpload});

  final SupabaseClient _db;
  final UploadTransport transport;

  static const bucket = 'documents';

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    return id;
  }

  Future<List<TackDocument>> all() async {
    try {
      final rows = await _db
          .from('documents')
          .select()
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return rows.map(TackDocument.fromRow).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Uploads a file.
  ///
  /// The row is created first with status `pending`, then the bytes go up, and
  /// only then does it become `ready`. A failure part-way leaves the row
  /// `failed` with a reason rather than a phantom document the student cannot
  /// see or delete.
  Future<TackDocument> upload({
    required DocumentType type,
    required String title,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final rejection = UploadRules.reject(
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
    if (rejection != null) throw Failure(rejection);

    final userId = _uid;
    String? documentId;

    try {
      final created = await _db
          .from('documents')
          .insert({
            'user_id': userId,
            'type': type.name,
            'title': title.trim(),
            // Provisional; replaced below once the id is known.
            'storage_path':
                'users/$userId/${type.name}/pending-${DateTime.now().microsecondsSinceEpoch}',
            'mime_type': mimeType,
            'size_bytes': bytes.length,
            'status': 'pending',
          })
          .select()
          .single();

      documentId = created['id'] as String;
      final key = UploadRules.storageKey(
        userId: userId,
        type: type,
        documentId: documentId,
      );

      await _db
          .from('documents')
          .update({'storage_path': key})
          .eq('id', documentId);

      final signed = await _db.storage.from(bucket).createSignedUploadUrl(key);

      await transport(
        url: Uri.parse(signed.signedUrl),
        bytes: bytes,
        contentType: mimeType,
        onProgress: (sent, total) =>
            onProgress?.call(total == 0 ? 0 : sent / total),
        isCancelled: isCancelled ?? () async => false,
      );

      // A CV goes to `processing` rather than `ready`: parsing runs in the
      // background and the student can leave the screen.
      final nextStatus = type == DocumentType.cv ? 'processing' : 'ready';
      final row = await _db
          .from('documents')
          .update({'status': nextStatus})
          .eq('id', documentId)
          .select()
          .single();

      return TackDocument.fromRow(row);
    } catch (e) {
      final failure = Failure.from(e);
      if (documentId != null) {
        await _db
            .from('documents')
            .update({'status': 'failed', 'failure_reason': failure.message})
            .eq('id', documentId);
      }
      throw failure;
    }
  }

  /// Asks the server to read a CV and score it.
  ///
  /// The endpoint answers 202 straight away and the reading happens on the
  /// queue, so this starts the work rather than waiting for it. A CV whose
  /// bytes have been read before comes back 200 with the score already
  /// attached and costs none of the day's AI actions.
  ///
  /// No text is sent: the document id is the whole request and the file is
  /// read server-side out of private storage. Sending the text from here would
  /// be handing the server a payload it can produce itself, and would put a
  /// route around redaction on the wrong side of the network.
  Future<void> requestScore(String documentId) async {
    try {
      await _db.functions.invoke('score-cv', body: {'documentId': documentId});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// A short-lived link to read one file.
  ///
  /// Five minutes, and only after the row has been fetched under the caller's
  /// own session — so an id belonging to someone else yields nothing to sign.
  Future<String> signedUrl(String documentId, {int ttlSeconds = 300}) async {
    try {
      final row = await _db
          .from('documents')
          .select('storage_path')
          .eq('id', documentId)
          .eq('user_id', _uid)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) {
        throw const Failure('That file is not available.');
      }
      return await _db.storage
          .from(bucket)
          .createSignedUrl(row['storage_path'] as String, ttlSeconds);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Promotes a CV to the default. Done through the database function so the
  /// previous default is demoted in the same statement — writing `is_default`
  /// directly trips a partial unique index.
  Future<void> makeDefault(String documentId) async {
    try {
      await _db.rpc<void>(
        'set_default_cv',
        params: {'p_document_id': documentId},
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> rename(String documentId, String title) async {
    try {
      await _db
          .from('documents')
          .update({'title': title.trim()})
          .eq('id', documentId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Soft delete. The object stays for 30 days, so an accidental delete is
  /// recoverable rather than final.
  Future<void> remove(String documentId) async {
    try {
      await _db
          .from('documents')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', documentId);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(supabaseProvider)),
);

final documentsProvider = FutureProvider<List<TackDocument>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(documentRepositoryProvider).all();
});

/// The CV that gets attached to an application unless the student picks
/// another one.
final defaultCvProvider = Provider<TackDocument?>((ref) {
  final documents =
      ref.watch(documentsProvider).value ?? const <TackDocument>[];
  final cvs = documents.where((d) => d.type == DocumentType.cv).toList();
  for (final cv in cvs) {
    if (cv.isDefault) return cv;
  }
  return cvs.isEmpty ? null : cvs.first;
});
