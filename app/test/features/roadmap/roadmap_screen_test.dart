import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/offline/local_db.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/roadmap/data/path_suggestion.dart';
import 'package:tack/features/roadmap/data/roadmap_models.dart';
import 'package:tack/features/roadmap/data/roadmap_repository.dart';
import 'package:tack/features/roadmap/presentation/journey_line.dart';
import 'package:tack/features/roadmap/presentation/roadmap_screen.dart';
import 'package:tack/features/roadmap/presentation/suggestion_card.dart';

import '../../helpers.dart';

RoadmapTask task(
  String title, {
  bool done = false,
  int points = 5,
  DateTime? due,
}) => RoadmapTask(
  id: 't-$title',
  milestoneId: 'm',
  title: title,
  type: TaskType.skill,
  points: points,
  isDone: done,
  dueDate: due,
);

RoadmapMilestone milestone(
  String title, {
  required MilestoneState state,
  required int order,
  List<RoadmapTask> tasks = const [],
  String? unlockText,
}) => RoadmapMilestone(
  id: 'm-$order',
  roadmapId: 'r1',
  orderIndex: order,
  title: title,
  state: state,
  tasks: tasks,
  unlockText: unlockText,
);

Roadmap roadmap({
  List<RoadmapMilestone>? milestones,
  int skipped = 0,
  String title = 'Frontend developer',
}) => Roadmap(
  id: 'r1',
  title: title,
  skippedCount: skipped,
  milestones:
      milestones ??
      [
        milestone(
          'Learn the three basics',
          state: MilestoneState.completed,
          order: 0,
          tasks: [task('HTML', done: true), task('CSS', done: true)],
        ),
        milestone(
          'Build with a framework',
          state: MilestoneState.active,
          order: 1,
          tasks: [task('React basics'), task('Fetch from an API')],
        ),
        milestone(
          'Prove it in public',
          state: MilestoneState.locked,
          order: 2,
          tasks: [task('Ship something')],
          unlockText: 'finish the framework steps',
        ),
      ],
);

PathSuggestion suggestion(
  String title, {
  int score = 40,
  List<String> reasons = const ['Your subject leads here'],
  bool isTarget = false,
  bool followed = false,
}) => PathSuggestion(
  id: 'p-$title',
  slug: title.toLowerCase().replaceAll(' ', '-'),
  title: title,
  score: score,
  reasons: reasons,
  summary: 'What a $title actually does all day.',
  salaryMin: 25000,
  salaryMax: 45000,
  months: 8,
  demand: 'very high',
  isTarget: isTarget,
  followed: followed,
);

List<Override> overrides(
  List<Roadmap> roadmaps, {
  PathAdvice advice = PathAdvice.empty,
}) => [
  pathAdviceProvider.overrideWith((ref) async => advice),
  localDbProvider.overrideWith((ref) {
    final db = LocalDb(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  connectivityProvider.overrideWith((ref) => Stream.value(true)),
  pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
  roadmapsProvider.overrideWith((ref) async => roadmaps),
];

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  setUpAll(loadTackFonts);

  testWidgets('the journey draws one spine segment per milestone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(JourneyLine), findsNWidgets(3));
  });

  testWidgets('a locked milestone says what opens it, never just a padlock', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Opens when you: finish the framework steps'),
      findsOneWidget,
    );
  });

  testWidgets('skipped steps are said out loud, not quietly dropped', (
    tester,
  ) async {
    // A roadmap shorter than a classmate's looks like a bug unless the app
    // explains itself.
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap(skipped: 4)]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '4 steps were left out because you already have those skills.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a roadmap with nothing skipped says nothing about it', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    expect(bodyText(tester), isNot(contains('left out')));
  });

  testWidgets('the percentage settles on the real figure', (tester) async {
    // Two of five done. TackCountUp animates, so a single pump would assert on
    // whatever the curve was passing through.
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('40%'), findsOneWidget);
    expect(bodyText(tester), contains('2 of 5 steps done'));
  });

  testWidgets('an impossible pace is named rather than hidden', (tester) async {
    // Twenty open steps due inside a fortnight. The alternative was silently
    // dropping steps until the arithmetic looked comfortable.
    final soon = DateTime.now().add(const Duration(days: 14));
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 2400),
      overrides: overrides([
        roadmap(
          milestones: [
            milestone(
              'A lot to do',
              state: MilestoneState.active,
              order: 0,
              tasks: [
                for (var i = 0; i < 20; i++) task('Step $i', due: soon),
              ],
            ),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(bodyText(tester), contains('which is a lot'));
  });

  testWidgets('no dates means no invented pace', (tester) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    final text = bodyText(tester);
    expect(text, contains('3 to go'));
    expect(text, isNot(contains('a week')));
  });

  testWidgets('an empty roadmap names the thing to do', (tester) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 900),
      overrides: overrides([]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No roadmap yet'), findsOneWidget);
    expect(find.text('Explore career paths'), findsOneWidget);

    // It sizes to its content. The shell no longer wraps the body in a scroll
    // view, so a bare child gets stretched to the full height — which turned
    // this card into a white slab running the length of the screen.
    //
    // The bound is tight on purpose: the broken version measured about 490,
    // so a looser assertion passed while the bug was on screen.
    expect(
      tester.getSize(find.byType(TackEmptyState)).height,
      lessThan(400),
    );
  });

  testWidgets('it lays out at the 360px floor without overflow', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 640),
      overrides: overrides([roadmap(skipped: 3)]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('one path gets no switcher chrome', (tester) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([roadmap()]),
    );
    await tester.pumpAndSettle();

    // Only the summary card names it; there is no chip to switch between one.
    expect(find.text('Frontend developer'), findsOneWidget);
  });

  testWidgets('two paths get a switcher', (tester) async {
    await pumpAt(
      tester,
      const RoadmapScreen(),
      size: const Size(360, 1400),
      overrides: overrides([
        roadmap(),
        Roadmap(
          id: 'r2',
          title: 'QA engineer',
          milestones: [
            milestone(
              'Learn to break things',
              state: MilestoneState.active,
              order: 0,
              tasks: [task('Write a test plan')],
            ),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // The chip renders "label count" as one string, so match the label part.
    expect(find.textContaining('QA engineer'), findsWidgets);
  });

  group('what Tack works out about you', () {
    testWidgets('with no roadmap it leads with the suggestions', (
      tester,
    ) async {
      // This screen used to be one empty card telling a student who had just
      // answered eight screens of questions to go and work it out themselves.
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 2000),
        overrides: overrides(
          [],
          advice: PathAdvice(
            field: 'Computer science and software',
            unsure: true,
            suggestions: [
              suggestion(
                'Backend developer',
                score: 80,
                isTarget: true,
                reasons: const ['You said this is what you are aiming at'],
              ),
              suggestion('QA engineer', score: 36),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Computer science and software'), findsOneWidget);
      expect(find.byType(SuggestionCard), findsNWidgets(2));
      expect(find.text('WHAT YOU SAID YOU WANT'), findsOneWidget);
    });

    testWidgets('every suggestion says why it is there', (tester) async {
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 2000),
        overrides: overrides(
          [],
          advice: PathAdvice(
            field: 'Design and creative arts',
            suggestions: [
              suggestion(
                'Graphic designer',
                reasons: const [
                  'You already have some of the skills it asks for',
                  'A subject you enjoy leads here',
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You already have some of the skills it asks for'),
        findsOneWidget,
      );
      expect(find.text('A subject you enjoy leads here'), findsOneWidget);
    });

    testWidgets('being unsure widens the list and says so', (tester) async {
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 2000),
        overrides: overrides(
          [],
          advice: PathAdvice(
            field: 'Business and management',
            unsure: true,
            suggestions: [suggestion('Business analyst')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(bodyText(tester), contains('not sure yet'));
      expect(bodyText(tester), contains('Nothing here commits you'));
    });

    testWidgets('nothing to go on falls back rather than inventing a ranking', (
      tester,
    ) async {
      // A student who has told us nothing must not be handed a confident list
      // built out of nothing.
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 900),
        overrides: overrides([], advice: PathAdvice.empty),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SuggestionCard), findsNothing);
      expect(find.text('No roadmap yet'), findsOneWidget);
    });

    testWidgets('a path already followed is marked, not re-sold', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 2000),
        overrides: overrides(
          [],
          advice: PathAdvice(
            field: 'Computer science and software',
            suggestions: [suggestion('Frontend developer', followed: true)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets('the suggestions lay out at the 360px floor', (tester) async {
      await pumpAt(
        tester,
        const RoadmapScreen(),
        size: const Size(360, 640),
        overrides: overrides(
          [],
          advice: PathAdvice(
            field: 'Computer science and software',
            suggestions: [
              suggestion('Backend developer', isTarget: true),
              suggestion('QA engineer'),
              suggestion('Frontend developer', followed: true),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}