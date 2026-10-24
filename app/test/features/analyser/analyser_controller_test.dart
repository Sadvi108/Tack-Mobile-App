import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/core/supabase/client.dart';
import 'package:tack/features/analyser/application/analyser_controller.dart';
import 'package:tack/features/analyser/data/analysis_models.dart';
import 'package:tack/features/analyser/data/analysis_repository.dart';

const _ready = AnalysisReady(
  JdAnalysis(
    analysisId: 'analysis-1',
    jobTitle: 'Junior analyst',
    skills: ['SQL'],
    qualifications: [],
    responsibilities: [],
  ),
  JdMatch.empty,
);

/// Stands in for the job's row. A test decides when the row "changes" and
/// what reading it returns. The Supabase client is never used.
class _FakeRepository extends AnalysisRepository {
  _FakeRepository({this.latest})
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final String? latest;
  final changes = StreamController<void>.broadcast();

  /// What reading the job returns. Null while it is still running.
  AnalysisState? result;
  int reads = 0;

  String? submittedJobId;

  @override
  Future<AnalysisState> submit(String text, {String? jobId}) async {
    submittedJobId = jobId;
    return const AnalysisQueued('job-1');
  }

  @override
  Future<String?> latestJob() async => latest;

  @override
  Future<AnalysisState?> poll(String jobId) async {
    reads++;
    return result;
  }

  @override
  Stream<void> jobChanges(String jobId) => changes.stream;
}

ProviderContainer _containerWith(_FakeRepository repository, {User? user}) =>
    ProviderContainer(
      overrides: [
        analysisRepositoryProvider.overrideWithValue(repository),
        currentUserProvider.overrideWithValue(user),
      ],
    );

Future<void> _analyse(ProviderContainer container) =>
    container.read(analyserControllerProvider.notifier).analyse('A job');

void main() {
  group('following an analysis', () {
    testWidgets('shows the result the moment the job changes', (tester) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      expect(container.read(analyserControllerProvider), isA<AnalysisQueued>());

      repository.result = _ready;
      repository.changes.add(null);
      await tester.pump();

      expect(container.read(analyserControllerProvider), same(_ready));
      expect(repository.reads, 1);
      container.dispose();
    });

    testWidgets('does not keep asking while the live connection is up', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      await tester.pump(const Duration(seconds: 29));

      // The old analyser asked every three seconds: nine reads by now.
      expect(repository.reads, 0);
      expect(container.read(analyserControllerProvider), isA<AnalysisQueued>());
      container.dispose();
    });

    testWidgets('still finds a result if the change is never heard', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      repository.result = _ready;
      await tester.pump(const Duration(seconds: 30));

      expect(container.read(analyserControllerProvider), same(_ready));
      container.dispose();
    });

    testWidgets('checks every few seconds again if the connection drops', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      repository.changes.addError(Exception('socket closed'));
      await tester.pump();

      // A dropped connection is not a failed analysis.
      expect(container.read(analyserControllerProvider), isA<AnalysisQueued>());

      repository.result = _ready;
      await tester.pump(const Duration(seconds: 3));

      expect(container.read(analyserControllerProvider), same(_ready));
      container.dispose();
    });

    testWidgets('lets the connection go once the result is in', (tester) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      expect(repository.changes.hasListener, isTrue);

      repository.result = _ready;
      repository.changes.add(null);
      await tester.pump();

      expect(repository.changes.hasListener, isFalse);
      container.dispose();
    });

    testWidgets('lets the connection go when the analyser is closed', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      expect(repository.changes.hasListener, isTrue);
      container.dispose();

      expect(repository.changes.hasListener, isFalse);
    });

    testWidgets('gives up after twelve minutes and says what to do', (
      tester,
    ) async {
      final repository = _FakeRepository();
      final container = _containerWith(repository);

      await _analyse(container);
      await tester.pump(const Duration(minutes: 12, seconds: 1));

      final state = container.read(analyserControllerProvider);
      expect(state, isA<AnalysisFailed>());
      expect(
        (state as AnalysisFailed).message,
        contains('Check back in a few minutes'),
      );
      expect(repository.changes.hasListener, isFalse);
      container.dispose();
    });
  });

  testWidgets('checking a saved job carries its id to the server', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final container = _containerWith(repository);

    await container
        .read(analyserControllerProvider.notifier)
        .analyse('A job', jobId: 'job-row-1');

    expect(repository.submittedJobId, 'job-row-1');
    container.dispose();
  });

  testWidgets('picks up a job left running when the analyser reopens', (
    tester,
  ) async {
    final repository = _FakeRepository(latest: 'job-1');
    final container = _containerWith(
      repository,
      user: User(
        id: 'student-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-10-22T00:00:00Z',
      ),
    );

    container.read(analyserControllerProvider);
    await tester.pump();
    expect(container.read(analyserControllerProvider), isA<AnalysisQueued>());
    expect(repository.changes.hasListener, isTrue);

    repository.result = _ready;
    repository.changes.add(null);
    await tester.pump();

    expect(container.read(analyserControllerProvider), same(_ready));
    container.dispose();
  });
}
