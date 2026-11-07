import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/ai/allowance.dart';
import 'package:tack/features/analyser/application/analyser_controller.dart';
import 'package:tack/features/analyser/application/cv_coverage.dart';
import 'package:tack/features/analyser/data/analysis_models.dart';
import 'package:tack/features/analyser/presentation/analyser_screen.dart';

import '../../helpers.dart';

class _Idle extends AnalyserController {
  @override
  AnalysisState build() => const AnalysisIdle();
}

class _Spent extends AnalyserController {
  @override
  AnalysisState build() => const AnalysisFailed(
    'You have used today\'s AI actions.',
    quotaExhausted: true,
  );
}

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
        (ref) async => const AiAllowance(used: 1, limit: 4),
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

  // The note before the work starts says what is left, never the whole
  // allowance: the limit is the server's, and it is not a student's number.
  group('before the work starts', () {
    setUpAll(loadTackFonts);

    testWidgets('the allowance note says what is left, not the limit', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const AnalyserScreen(),
        size: const Size(360, 1200),
        overrides: [
          analyserControllerProvider.overrideWith(_Idle.new),
          aiAllowanceProvider.overrideWith(
            (ref) async => const AiAllowance(used: 1, limit: 4),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '3 AI actions left today, shared across Tack. They reset at midnight.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('of 4'), findsNothing);
      expect(hasOverflow(tester), isFalse);
    });

    // The quota state explains the trade. It used to print the daily number
    // twice ("Every student gets N a day ... Your next N arrive").
    testWidgets('a spent allowance explains the trade, never the number', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const AnalyserScreen(),
        size: const Size(360, 1200),
        overrides: [
          analyserControllerProvider.overrideWith(_Spent.new),
          aiAllowanceProvider.overrideWith(
            (ref) async => const AiAllowance(used: 4, limit: 4),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('You have used today\'s AI actions'), findsOneWidget);
      expect(
        find.text(
          'The daily limit is what keeps Tack free for everyone. Plenty here '
          'costs nothing: the CV check, interview practice with self-checks, '
          'Radar and your roadmap. More arrive at midnight.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(find.text('Work on your roadmap instead'), findsOneWidget);
      expect(hasOverflow(tester), isFalse);
    });
  });
}
