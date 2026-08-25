import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/dashboard/application/next_actions.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/roadmap/data/roadmap_models.dart';
import 'package:tack/features/score/data/readiness.dart';

ReadinessScore scoreWith(
  Map<String, (int earned, int max)> components, {
  YearMode mode = YearMode.launch,
}) => ReadinessScore(
  total: components.values.fold(0, (s, c) => s + c.$1),
  mode: mode,
  delta: 0,
  computedAt: DateTime(2026, 8, 25),
  components: [
    for (final e in components.entries)
      ScoreComponent(
        key: e.key,
        earned: e.value.$1,
        max: e.value.$2,
        ratio: e.value.$2 == 0 ? 0 : e.value.$1 / e.value.$2,
      ),
  ],
);

Roadmap roadmapWith(
  List<RoadmapTask> tasks, {
  MilestoneState state = MilestoneState.active,
}) => Roadmap(
  id: 'r1',
  title: 'Frontend developer',
  milestones: [
    RoadmapMilestone(
      id: 'm1',
      roadmapId: 'r1',
      orderIndex: 0,
      title: 'Learn the three basics',
      state: state,
      tasks: tasks,
    ),
  ],
);

RoadmapTask task(
  String id,
  String title, {
  int points = 4,
  int? minutes,
  bool done = false,
}) => RoadmapTask(
  id: id,
  milestoneId: 'm1',
  title: title,
  type: TaskType.skill,
  points: points,
  isDone: done,
  estMinutes: minutes,
);

void main() {
  test('returns at most three actions', () {
    final actions = rankNextActions(
      score: scoreWith({
        'cv_quality': (0, 13),
        'skills': (2, 12),
        'projects': (0, 10),
        'interview_practice': (0, 9),
        'certifications': (0, 6),
      }),
      roadmaps: const [],
    );
    expect(actions, hasLength(3));
  });

  test('a quick win outranks a bigger prize that takes far longer', () {
    // Projects are worth more in total but cost days. Skills are worth less
    // and take five minutes, so a student with a spare moment sees skills.
    final actions = rankNextActions(
      score: scoreWith({'projects': (0, 10), 'skills': (2, 12)}),
      roadmaps: const [],
      limit: 2,
    );
    expect(actions.first.componentKey, 'skills');
    expect(actions.last.componentKey, 'projects');
  });

  test('every action carries the points it is worth', () {
    final actions = rankNextActions(
      score: scoreWith({'cv_quality': (0, 13)}),
      roadmaps: const [],
    );
    expect(actions.single.points, 13);
    expect(actions.single.title, 'Upload your CV so it can be checked');
  });

  test('components this year does not count are never offered', () {
    // In explore mode application activity is weighted zero on purpose. A
    // first-year must never be told to go and apply for jobs.
    final actions = rankNextActions(
      score: scoreWith({
        'application_activity': (0, 0),
        'skills': (0, 16),
      }, mode: YearMode.explore),
      roadmaps: const [],
    );
    expect(
      actions.map((a) => a.componentKey),
      isNot(contains('application_activity')),
    );
    expect(actions.map((a) => a.componentKey), contains('skills'));
  });

  test('a fully earned component is not offered again', () {
    final actions = rankNextActions(
      score: scoreWith({'skills': (12, 12), 'projects': (0, 10)}),
      roadmaps: const [],
    );
    expect(actions.map((a) => a.componentKey), ['projects']);
  });

  test('open roadmap tasks are ranked alongside score components', () {
    final actions = rankNextActions(
      score: scoreWith({'projects': (0, 10)}),
      roadmaps: [
        roadmapWith([
          task('t1', 'Put your code on GitHub', points: 2, minutes: 60),
        ]),
      ],
    );
    expect(actions.any((a) => a.taskId == 't1'), isTrue);
  });

  test('finished tasks and locked milestones contribute nothing', () {
    final done = rankNextActions(
      score: scoreWith({}),
      roadmaps: [
        roadmapWith([task('t1', 'Already done', done: true)]),
      ],
    );
    expect(done, isEmpty);

    final locked = rankNextActions(
      score: scoreWith({}),
      roadmaps: [
        roadmapWith([task('t2', 'Not open yet')], state: MilestoneState.locked),
      ],
    );
    expect(locked, isEmpty);
  });

  test('the same thing is never suggested twice', () {
    // Two components may legitimately share a destination; what must not
    // repeat is the advice itself.
    final actions = rankNextActions(
      score: scoreWith({
        'profile_completeness': (0, 8),
        'skills': (0, 12),
        'certifications': (0, 6),
        'cv_quality': (0, 13),
      }),
      roadmaps: const [],
    );
    final titles = actions.map((a) => a.title).toList();
    expect(titles.toSet(), hasLength(titles.length));

    final keys = actions.map((a) => a.componentKey).toList();
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('an empty account still produces something to do', () {
    final actions = rankNextActions(
      score: scoreWith({
        'profile_completeness': (1, 8),
        'cv_quality': (0, 13),
        'skills': (0, 12),
      }),
      roadmaps: const [],
    );
    expect(actions, isNotEmpty);
    expect(actions.every((a) => a.points > 0), isTrue);
  });
}
