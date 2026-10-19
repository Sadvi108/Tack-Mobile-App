import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/analyser/application/analyser_controller.dart';
import 'package:tack/features/analyser/application/cv_coverage.dart';
import 'package:tack/features/analyser/data/analysis_models.dart';
import 'package:tack/features/analyser/presentation/analyser_screen.dart';
import 'package:tack/features/coach/data/coach_repository.dart';

import '../../helpers.dart';

class _Ready extends AnalyserController {
  @override
  AnalysisState build() => const AnalysisReady(
    JdAnalysis(
      analysisId: 'a1',
      jobTitle: 'Data analyst',
      skills: ['SQL', 'Power BI', 'Node.js'],
      qualifications: [],
      responsibilities: [],
    ),
    JdMatch(
      matchPercent: 67,
      matched: ['SQL', 'Node.js'],
      missing: ['Power BI'],
    ),
  );
}

void main() {
  group('cv coverage', () {
    test('splits matched skills by what the CV check found', () {
      final coverage = cvCoverage(
        ['SQL', 'Excel', 'Python'],
        ['sql', 'Python'],
      );
      expect(coverage.shown, ['SQL', 'Python']);
      expect(coverage.hidden, ['Excel']);
    });

    test('uses the same loose equality as the server match', () {
      final coverage = cvCoverage(['Node.js', 'C++'], ['NodeJS', 'c++']);
      expect(coverage.hidden, isEmpty);
    });

    test('an empty CV check hides everything, it never errors', () {
      expect(cvCoverage(['SQL'], const []).hidden, ['SQL']);
      expect(cvCoverage(const [], const ['SQL']).shown, isEmpty);
    });
  });

  group('the analyser result', () {
    setUpAll(loadTackFonts);

    List<Override> overrides(List<String>? cvSkills) => [
      analyserControllerProvider.overrideWith(_Ready.new),
      aiAllowanceProvider.overrideWith(
        (ref) async => const AiAllowance(used: 1, limit: 10),
      ),
      latestCvSkillsProvider.overrideWith((ref) async => cvSkills),
    ];

    testWidgets('names the skills the CV does not show', (tester) async {
      await pumpAt(
        tester,
        const AnalyserScreen(),
        size: const Size(360, 2000),
        overrides: overrides(['SQL']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not on your CV yet'), findsOneWidget);
      // Node.js is in the profile and the job, but not on the CV.
      expect(find.text('Node.js'), findsNWidgets(2));
      expect(hasOverflow(tester), isFalse);
    });

    testWidgets('a CV that shows everything says so plainly', (tester) async {
      await pumpAt(
        tester,
        const AnalyserScreen(),
        size: const Size(360, 2000),
        overrides: overrides(['SQL', 'NodeJS']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not on your CV yet'), findsNothing);
      expect(find.textContaining('Your CV shows all 2'), findsOneWidget);
    });

    testWidgets('no CV check yet points to the free check', (tester) async {
      await pumpAt(
        tester,
        const AnalyserScreen(),
        size: const Size(360, 2000),
        overrides: overrides(null),
      );
      await tester.pumpAndSettle();

      expect(find.text('Can hiring software see these?'), findsOneWidget);
      expect(find.text('Check my CV'), findsOneWidget);
    });
  });
}
