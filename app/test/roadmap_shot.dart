import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/roadmap/data/path_suggestion.dart';
import 'package:tack/features/roadmap/data/roadmap_models.dart';
import 'package:tack/features/roadmap/presentation/roadmap_screen.dart';

import 'features/roadmap/roadmap_screen_test.dart' as fx;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('the journey', (tester) async {
    final due = DateTime.now().add(const Duration(days: 21));
    await shoot(
      tester,
      const RoadmapScreen(),
      'roadmap',
      const Size(390, 844),
      overrides: fx.overrides([
        fx.roadmap(
          skipped: 3,
          milestones: [
            fx.milestone(
              'Learn the three basics',
              state: MilestoneState.completed,
              order: 0,
              tasks: [
                fx.task('Build a static page from scratch', done: true),
                fx.task('Write 20 small JavaScript exercises', done: true),
                fx.task('Make one page work at 360px', done: true),
              ],
            ),
            fx.milestone(
              'Build with a framework',
              state: MilestoneState.active,
              order: 1,
              tasks: [
                fx.task('Learn React components and state', done: true),
                fx.task('Build a to-do app that saves data', due: due),
                fx.task('Learn to fetch data from a public API', due: due),
                fx.task('Deploy one project to a live URL'),
              ],
            ),
            fx.milestone(
              'Make it look designed',
              state: MilestoneState.locked,
              order: 2,
              tasks: [fx.task('Learn spacing and type scale')],
              unlockText: 'finish the framework steps',
            ),
            fx.milestone(
              'Apply and interview',
              state: MilestoneState.locked,
              order: 3,
              tasks: [fx.task('Send five real applications')],
              unlockText: 'have three deployed projects',
            ),
          ],
        ),
      ]),
      panels: const [0, 560],
    );
  });

  // Exactly what path_suggestions() returns for the live account: a Computer
  // Science major, a stated target of Backend developer, four industries, and
  // a recorded confidence of "unsure".
  testWidgets('what Tack works out about you', (tester) async {
    await shoot(
      tester,
      const RoadmapScreen(),
      'roadmap-suggestions',
      const Size(390, 844),
      overrides: fx.overrides(
        [],
        advice: const PathAdvice(
          field: 'Computer science and software',
          unsure: true,
          suggestions: [
            PathSuggestion(
              id: '1',
              slug: 'backend-developer',
              title: 'Backend developer',
              score: 80,
              isTarget: true,
              reasons: [
                'You said this is what you are aiming at',
                'It is in an industry you picked',
              ],
              summary:
                  'You build the part nobody sees: the data, the rules and the '
                  'APIs the screens talk to.',
              salaryMin: 28000,
              salaryMax: 50000,
              months: 10,
              demand: 'very high',
            ),
            PathSuggestion(
              id: '2',
              slug: 'qa-engineer',
              title: 'QA engineer',
              score: 36,
              reasons: [
                'Your subject leads here',
                'It is in an industry you picked',
              ],
              summary:
                  'You find what is broken before a customer does, and build '
                  'the tests that keep it fixed.',
              salaryMin: 22000,
              salaryMax: 40000,
              months: 7,
              demand: 'high',
            ),
            PathSuggestion(
              id: '3',
              slug: 'frontend-developer',
              title: 'Frontend developer',
              score: 35,
              followed: true,
              reasons: [
                'Your subject leads here',
                'It is in an industry you picked',
              ],
              summary:
                  'You build the part of a website or app that people actually '
                  'see and click.',
              salaryMin: 25000,
              salaryMax: 45000,
              months: 8,
              demand: 'very high',
            ),
          ],
        ),
      ),
      panels: const [0, 620],
    );
  });
}