import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/dashboard/application/dashboard_data.dart';
import 'package:tack/features/paths/data/path_repository.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/score/data/readiness.dart';
import 'package:tack/features/vault/data/document_models.dart';

ReadinessScore scoreWith(Map<String, (int earned, int max)> components) =>
    ReadinessScore(
      total: 0,
      mode: YearMode.launch,
      components: [
        for (final entry in components.entries)
          ScoreComponent(
            key: entry.key,
            earned: entry.value.$1,
            max: entry.value.$2,
            ratio: entry.value.$2 == 0 ? 0 : entry.value.$1 / entry.value.$2,
          ),
      ],
      delta: 0,
      computedAt: DateTime(2026),
    );

TackDocument cv({DocumentStatus status = DocumentStatus.ready}) => TackDocument(
  id: 'd1',
  type: DocumentType.cv,
  title: 'CV',
  storagePath: 'users/u/cv/d1',
  status: status,
  createdAt: DateTime(2026),
);

final launchScore = scoreWith({
  'cv_quality': (0, 13),
  'application_activity': (0, 14),
});

void main() {
  group('what is left to set up', () {
    test('a brand-new final-year is asked for all three', () {
      final steps = setupSteps(
        score: launchScore,
        documents: const [],
        chosenPaths: const [],
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), [
        'Upload your CV',
        'Pick a target job',
        'Add your first application',
      ]);
    });

    test('point values come from the score engine, not from the card', () {
      final steps = setupSteps(
        score: launchScore,
        documents: const [],
        chosenPaths: const [],
        applicationCount: 0,
      );

      expect(steps.first.points, 13);
      expect(steps.last.points, 14);
    });

    test('a step already done drops out', () {
      final steps = setupSteps(
        score: launchScore,
        documents: [cv()],
        chosenPaths: const [ChosenPath(pathId: 'p1', isPrimary: true)],
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), ['Add your first application']);
    });

    test('once everything is done the card has nothing to show', () {
      final steps = setupSteps(
        score: launchScore,
        documents: [cv()],
        chosenPaths: const [ChosenPath(pathId: 'p1', isPrimary: true)],
        applicationCount: 2,
      );

      expect(steps, isEmpty);
    });

    test('a CV that failed to upload does not count as having one', () {
      final steps = setupSteps(
        score: launchScore,
        documents: [cv(status: DocumentStatus.failed)],
        chosenPaths: const [],
        applicationCount: 0,
      );

      expect(steps.first.title, 'Upload your CV');
    });

    test('a CV still being read does count — it is already uploaded', () {
      final steps = setupSteps(
        score: launchScore,
        documents: [cv(status: DocumentStatus.processing)],
        chosenPaths: const [],
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), isNot(contains('Upload your CV')));
    });

    test('a first-year is never told to apply for anything', () {
      // application_activity is weighted zero in explore mode on purpose. A
      // step worth nothing in this student's mode is not a step.
      final steps = setupSteps(
        score: scoreWith({
          'cv_quality': (0, 6),
          'application_activity': (0, 0),
        }),
        documents: const [],
        chosenPaths: const [],
        applicationCount: 0,
      );

      expect(
        steps.map((s) => s.title),
        isNot(contains('Add your first application')),
      );
      expect(steps.map((s) => s.title), contains('Upload your CV'));
    });

    test('picking a path is worth saying even though it scores nothing', () {
      final steps = setupSteps(
        score: launchScore,
        documents: [cv()],
        chosenPaths: const [],
        applicationCount: 5,
      );

      expect(steps.single.title, 'Pick a target job');
      expect(steps.single.points, 0);
    });
  });
}
