import '../../../design/tack.dart';

/// A job the student saved or applied to.
class JobApplication {
  const JobApplication({
    required this.id,
    required this.jobId,
    required this.status,
    required this.title,
    this.companyName,
    this.location,
    this.sourceUrl,
    this.appliedAt,
    this.nextAction,
    this.nextActionDate,
    this.cvDocumentId,
    this.notes,
    this.closesAt,
    this.updatedAt,
  });

  final String id;
  final String jobId;
  final TackStatus status;
  final String title;
  final String? companyName;
  final String? location;
  final String? sourceUrl;
  final DateTime? appliedAt;
  final String? nextAction;
  final DateTime? nextActionDate;
  final String? cvDocumentId;
  final String? notes;
  final DateTime? closesAt;
  final DateTime? updatedAt;

  bool get isOpen => status != TackStatus.rejected && status != TackStatus.offer;

  /// Days until the next thing has to happen. Negative when it is overdue.
  int? get daysUntilNextAction {
    final date = nextActionDate;
    if (date == null) return null;
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  factory JobApplication.fromRow(Map<String, dynamic> row) {
    final job = (row['jobs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final company = (job['companies'] as Map?)?.cast<String, dynamic>();
    return JobApplication(
      id: row['id'] as String,
      jobId: row['job_id'] as String,
      status: TackStatusStyle.fromWire('${row['status']}'),
      title: (job['title'] as String?) ?? 'Untitled role',
      companyName: (company?['name'] as String?) ?? job['company_name'] as String?,
      location: job['location'] as String?,
      sourceUrl: job['source_url'] as String?,
      closesAt: DateTime.tryParse('${job['closes_at']}'),
      appliedAt: DateTime.tryParse('${row['applied_at']}')?.toLocal(),
      nextAction: row['next_action'] as String?,
      nextActionDate: DateTime.tryParse('${row['next_action_date']}'),
      cvDocumentId: row['cv_document_id'] as String?,
      notes: row['notes'] as String?,
      updatedAt: DateTime.tryParse('${row['updated_at']}')?.toLocal(),
    );
  }
}

/// One entry in the status timeline on the detail screen.
class StatusChange {
  const StatusChange({
    required this.toStatus,
    required this.changedAt,
    this.fromStatus,
    this.note,
  });

  final TackStatus toStatus;
  final TackStatus? fromStatus;
  final DateTime changedAt;
  final String? note;

  factory StatusChange.fromRow(Map<String, dynamic> row) => StatusChange(
        toStatus: TackStatusStyle.fromWire('${row['to_status']}'),
        fromStatus: row['from_status'] == null
            ? null
            : TackStatusStyle.fromWire('${row['from_status']}'),
        changedAt: DateTime.tryParse('${row['changed_at']}')?.toLocal() ?? DateTime.now(),
        note: row['note'] as String?,
      );
}

/// The counts behind the filter strip and the funnel.
class ApplicationCounts {
  const ApplicationCounts(this.byStatus);

  final Map<TackStatus, int> byStatus;

  static const empty = ApplicationCounts({});

  int operator [](TackStatus status) => byStatus[status] ?? 0;

  int get total => byStatus.values.fold(0, (a, b) => a + b);

  /// Keyed by wire name, for the funnel widget.
  Map<String, int> get asWireMap =>
      {for (final e in byStatus.entries) e.key.name: e.value};
}
