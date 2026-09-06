import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

/// Whatever the app last read from the server, so a student on a train sees
/// their roadmap instead of a spinner.
class CachedReads extends Table {
  /// A stable key for one query, e.g. `roadmaps` or `applications:all`.
  TextColumn get key => text()();

  /// The raw JSON the server returned.
  TextColumn get payload => text()();

  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Changes made while offline, waiting to be sent.
///
/// Tack is read-write offline for tasks and applications: a student can tick a
/// task on a bus and it lands when they get signal. This is the queue that
/// makes that true rather than a claim.
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// What kind of change: `task_done`, `application_status`, `application_notes`.
  TextColumn get kind => text()();

  /// The row this change applies to.
  TextColumn get targetId => text()();

  /// The change itself, as JSON.
  TextColumn get payload => text()();

  DateTimeColumn get queuedAt => dateTime()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();
}

@DriftDatabase(tables: [CachedReads, Outbox])
class LocalDb extends _$LocalDb {
  LocalDb([QueryExecutor? executor, this.accountId = 'legacy'])
    : super(executor ?? driftDatabase(name: 'tack_local_$accountId'));

  final String accountId;

  @override
  int get schemaVersion => 1;

  // ------------------------------------------------------------------ cache
  Future<void> putCache(String key, String payload) =>
      into(cachedReads).insertOnConflictUpdate(
        CachedReadsCompanion.insert(
          key: key,
          payload: payload,
          fetchedAt: DateTime.now(),
        ),
      );

  Future<CachedRead?> readCache(String key) =>
      (select(cachedReads)..where((t) => t.key.equals(key))).getSingleOrNull();

  Future<void> clearCache() => delete(cachedReads).go();

  // ----------------------------------------------------------------- outbox
  Future<int> enqueue({
    required String kind,
    required String targetId,
    required String payload,
  }) async {
    // One pending change per target per kind. A student who ticks and unticks
    // a task five times offline should send one change, not five.
    return transaction(() async {
      await (delete(
        outbox,
      )..where((t) => t.kind.equals(kind) & t.targetId.equals(targetId))).go();

      return into(outbox).insert(
        OutboxCompanion.insert(
          kind: kind,
          targetId: targetId,
          payload: payload,
          queuedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<List<OutboxData>> pending({int limit = 50}) =>
      (select(outbox)
            ..orderBy([(t) => OrderingTerm(expression: t.queuedAt)])
            ..limit(limit))
          .get();

  Stream<int> watchPendingCount() =>
      (selectOnly(outbox)..addColumns([outbox.id.count()]))
          .map((row) => row.read(outbox.id.count()) ?? 0)
          .watchSingle();

  Future<int> pendingCount() async {
    final rows = await (selectOnly(
      outbox,
    )..addColumns([outbox.id.count()])).getSingle();
    return rows.read(outbox.id.count()) ?? 0;
  }

  Stream<List<OutboxData>> watchProblems() =>
      (select(outbox)
            ..where((t) => t.attempts.isBiggerThanValue(0))
            ..orderBy([(t) => OrderingTerm(expression: t.queuedAt)]))
          .watch();

  Future<void> discard(int id) =>
      (delete(outbox)..where((t) => t.id.equals(id))).go();

  Future<void> bumpAttempts(int id, int attempts, String error) =>
      (update(outbox)..where((t) => t.id.equals(id))).write(
        OutboxCompanion(attempts: Value(attempts), lastError: Value(error)),
      );
}
