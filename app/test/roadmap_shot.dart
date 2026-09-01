import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
