enum DocumentType {
  cv,
  certificate,
  project,
  transcript,
  other;

  static DocumentType fromWire(String? value) => DocumentType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => DocumentType.other,
  );

  String get label => switch (this) {
    DocumentType.cv => 'CV',
    DocumentType.certificate => 'Certificate',
    DocumentType.project => 'Project file',
    DocumentType.transcript => 'Transcript',
    DocumentType.other => 'Other',
  };

  String get plural => switch (this) {
    DocumentType.cv => 'CVs',
    DocumentType.certificate => 'Certificates',
    DocumentType.project => 'Project files',
    DocumentType.transcript => 'Transcripts',
    DocumentType.other => 'Other files',
  };
}

enum DocumentStatus {
  pending,
  processing,
  ready,
  failed;

  static DocumentStatus fromWire(String? value) => DocumentStatus.values
      .firstWhere((s) => s.name == value, orElse: () => DocumentStatus.pending);
}

class TackDocument {
  const TackDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.storagePath,
    required this.status,
    this.mimeType,
    this.sizeBytes,
    this.isDefault = false,
    this.version = 1,
    this.parentDocumentId,
    this.failureReason,
    required this.createdAt,
  });

  final String id;
  final DocumentType type;
  final String title;
  final String storagePath;
  final DocumentStatus status;
  final String? mimeType;
  final int? sizeBytes;
  final bool isDefault;
  final int version;
  final String? parentDocumentId;
  final String? failureReason;
  final DateTime createdAt;

  bool get isReady => status == DocumentStatus.ready;
  bool get isProcessing => status == DocumentStatus.processing;

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory TackDocument.fromRow(Map<String, dynamic> row) => TackDocument(
    id: row['id'] as String,
    type: DocumentType.fromWire(row['type'] as String?),
    title: row['title'] as String,
    storagePath: row['storage_path'] as String,
    status: DocumentStatus.fromWire(row['status'] as String?),
    mimeType: row['mime_type'] as String?,
    sizeBytes: (row['size_bytes'] as num?)?.toInt(),
    isDefault: row['is_default'] as bool? ?? false,
    version: (row['version'] as num?)?.toInt() ?? 1,
    parentDocumentId: row['parent_document_id'] as String?,
    failureReason: row['failure_reason'] as String?,
    createdAt:
        DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
  );
}

/// What the vault will accept, checked on this device before anything is sent
/// so the student gets a readable sentence instead of a failed request.
class UploadRules {
  const UploadRules._();

  static const maxBytes = 10 * 1024 * 1024;

  static const allowedMimeTypes = <String>{
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  /// Returns null when the file is fine, or a sentence explaining what to do.
  static String? reject({required String? mimeType, required int sizeBytes}) {
    if (sizeBytes <= 0) return 'That file is empty. Pick another one.';
    if (sizeBytes > maxBytes) {
      final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      return 'That file is ${mb}MB. The limit is 10MB — try a smaller version.';
    }
    if (mimeType == null || !allowedMimeTypes.contains(mimeType)) {
      return 'Tack takes PDFs, Word files and photos. Try one of those.';
    }
    return null;
  }

  /// Storage keys are `users/{userId}/{type}/{documentId}`.
  ///
  /// This shape is not cosmetic: the storage policies read ownership straight
  /// off the path, so a key built any other way is rejected by the server.
  static String storageKey({
    required String userId,
    required DocumentType type,
    required String documentId,
  }) => 'users/$userId/${type.name}/$documentId';
}
