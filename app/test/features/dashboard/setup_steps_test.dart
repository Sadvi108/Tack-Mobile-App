import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/dashboard/application/dashboard_data.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/score/data/readiness.dart';

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

final launchScore = scoreWith({
  'cv_quality': (0, 13),
  'application_activity': (0, 14),
});

void main() {
  group('what is left to set up', () {
    test('a brand-new final-year is asked for all three', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: false,
        chosenPathCount: 0,
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), [
        'Upload your CV',
        'Pick a target job',
        'Add your first application',
      ]);
    });

    test('point values come from the score engine, not from the card', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: false,
        chosenPathCount: 0,
        applicationCount: 0,
      );

      expect(steps.first.points, 13);
      expect(steps.last.points, 14);
    });

    test('a step already done drops out', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: true,
        chosenPathCount: 1,
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), ['Add your first application']);
    });

    test('once everything is done the card has nothing to show', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: true,
        chosenPathCount: 1,
        applicationCount: 2,
      );

      expect(steps, isEmpty);
    });

    // The feed decides what counts as having a CV: a failed upload does not,
    // and one still being parsed does. Both are asserted against the live
    // database in tool/verify_dashboard.js, because that rule is now SQL.
    test('no CV means the step is still there', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: false,
        chosenPathCount: 0,
        applicationCount: 0,
      );

      expect(steps.first.title, 'Upload your CV');
    });

    test('a CV the feed reports drops the step', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: true,
        chosenPathCount: 0,
        applicationCount: 0,
      );

      expect(steps.map((s) => s.title), isNot(contains('Upload your CV')));
    });

    test('a first-year is never told to apply for anything', () {
      // application_activity is weighted zero in explore mode on purpose. A
      // step worth nothing in this student's mode is not a step.
      final steps = remainingSetupSteps(
        score: scoreWith({
          'cv_quality': (0, 6),
          'application_activity': (0, 0),
        }),
        hasCv: false,
        chosenPathCount: 0,
        applicationCount: 0,
      );

      expect(
        steps.map((s) => s.title),
        isNot(contains('Add your first application')),
      );
      expect(steps.map((s) => s.title), contains('Upload your CV'));
    });

    test('picking a path is worth saying even though it scores nothing', () {
      final steps = remainingSetupSteps(
        score: launchScore,
        hasCv: true,
        chosenPathCount: 0,
        applicationCount: 5,
      );

      expect(steps.single.title, 'Pick a target job');
      expect(steps.single.points, 0);
    });
  });
}
