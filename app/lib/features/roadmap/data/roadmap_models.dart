/// The six kinds of roadmap task, each with its own tint pair.
enum TaskType {
  skill,
  project,
  certificate,
  networking,
  application,
  cv;

  static TaskType fromWire(String? value) => TaskType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => TaskType.skill,
  );

  String get label => switch (this) {
    TaskType.skill => 'Skill',
    TaskType.project => 'Project',
    TaskType.certificate => 'Certificate',
    TaskType.networking => 'Networking',
    TaskType.application => 'Application',
    TaskType.cv => 'CV',
  };
}

enum MilestoneState {
  locked,
  active,
  completed;

  static MilestoneState fromWire(String? value) => MilestoneState.values
      .firstWhere((s) => s.name == value, orElse: () => MilestoneState.locked);
}

class RoadmapTask {
  const RoadmapTask({
    required this.id,
    required this.milestoneId,
    required this.title,
    required this.type,
    required this.points,
    required this.isDone,
    this.estMinutes,
    this.dueDate,
    this.isCustom = false,
    this.orderIndex = 0,
    this.sharedWithRoadmaps = const [],
  });

  final String id;
  final String milestoneId;
  final String title;
  final TaskType type;
  final int points;
  final bool isDone;
  final int? estMinutes;
  final DateTime? dueDate;
  final bool isCustom;
  final int orderIndex;

  /// When two career paths share a task, finishing it counts toward both.
  final List<String> sharedWithRoadmaps;

  bool get isShared => sharedWithRoadmaps.length > 1;

  bool get isOverdue =>
      !isDone && dueDate != null && dueDate!.isBefore(DateTime.now());

  factory RoadmapTask.fromRow(Map<String, dynamic> row) => RoadmapTask(
    id: row['id'] as String,
    milestoneId: row['milestone_id'] as String,
    title: row['title'] as String,
    type: TaskType.fromWire(row['type'] as String?),
    points: (row['points'] as num?)?.toInt() ?? 0,
    isDone: row['is_done'] as bool? ?? false,
    estMinutes: (row['est_minutes'] as num?)?.toInt(),
    dueDate: DateTime.tryParse('${row['due_date']}'),
    isCustom: row['is_custom'] as bool? ?? false,
    orderIndex: (row['order_index'] as num?)?.toInt() ?? 0,
    sharedWithRoadmaps:
        (row['shared_with_roadmaps'] as List?)?.cast<String>() ?? const [],
  );
}

class RoadmapMilestone {
  const RoadmapMilestone({
    required this.id,
    required this.roadmapId,
    required this.orderIndex,
    required this.title,
    required this.state,
    this.description,
    this.unlockText,
    this.typicalSemester,
    this.tasks = const [],
  });

  final String id;
  final String roadmapId;
  final int orderIndex;
  final String title;
  final MilestoneState state;
  final String? description;

  /// What opens this milestone. A locked milestone always says what unlocks it
  /// rather than showing a padlock alone — the sequence must read as a route,
  /// not a paywall.
  final String? unlockText;
  final int? typicalSemester;
  final List<RoadmapTask> tasks;

  int get doneCount => tasks.where((t) => t.isDone).length;
  int get totalCount => tasks.length;
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;
  int get pointsAvailable =>
      tasks.where((t) => !t.isDone).fold(0, (sum, t) => sum + t.points);

  factory RoadmapMilestone.fromRow(Map<String, dynamic> row) {
    final rawTasks = (row['roadmap_tasks'] as List?) ?? const [];
    final tasks =
        rawTasks.cast<Map<String, dynamic>>().map(RoadmapTask.fromRow).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return RoadmapMilestone(
      id: row['id'] as String,
      roadmapId: row['roadmap_id'] as String,
      orderIndex: (row['order_index'] as num?)?.toInt() ?? 0,
      title: row['title'] as String,
      state: MilestoneState.fromWire(row['state'] as String?),
      description: row['description'] as String?,
      unlockText: row['unlock_text'] as String?,
      typicalSemester: (row['typical_semester'] as num?)?.toInt(),
      tasks: tasks,
    );
  }

  RoadmapMilestone copyWith({List<RoadmapTask>? tasks}) => RoadmapMilestone(
    id: id,
    roadmapId: roadmapId,
    orderIndex: orderIndex,
    title: title,
    state: state,
    description: description,
    unlockText: unlockText,
    typicalSemester: typicalSemester,
    tasks: tasks ?? this.tasks,
  );
}

class Roadmap {
  const Roadmap({
    required this.id,
    required this.title,
    this.pathId,
    this.pathSlug,
    this.milestones = const [],
    this.skippedCount = 0,
  });

  final String id;
  final String title;
  final String? pathId;
  final String? pathSlug;
  final List<RoadmapMilestone> milestones;

  /// Template steps left out because the student already holds the skill they
  /// teach, at proficiency 3 or better.
  ///
  /// Shown rather than kept quiet: a roadmap that is shorter than a
  /// classmate's looks like a bug unless the app says why.
  final int skippedCount;

  List<RoadmapTask> get allTasks => [for (final m in milestones) ...m.tasks];

  int get doneCount => allTasks.where((t) => t.isDone).length;
  int get totalCount => allTasks.length;
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;

  List<RoadmapTask> get openTasks =>
      allTasks.where((t) => !t.isDone).toList(growable: false);

  /// The last date anything is due, which is as close as the roadmap gets to
  /// knowing when the student means to finish.
  DateTime? get finishBy {
    DateTime? latest;
    for (final task in allTasks) {
      final due = task.dueDate;
      if (due == null) continue;
      if (latest == null || due.isAfter(latest)) latest = due;
    }
    return latest;
  }

  /// Steps a week needed to finish everything still open before [finishBy].
  ///
  /// Null when there is nothing left, or no dates to work back from. This is
  /// deliberately not used to shrink the roadmap: a final-year with four
  /// months and twenty-nine steps is behind, and saying so plainly is more
  /// use than quietly deleting the steps they would have missed.
  double? pacePerWeek(DateTime today) {
    final open = openTasks.length;
    final end = finishBy;
    if (open == 0 || end == null) return null;
    final days = end.difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days <= 0) return null;
    return open / (days / 7);
  }

  /// The milestone the student is on, or the first unfinished one.
  RoadmapMilestone? get activeMilestone {
    for (final m in milestones) {
      if (m.state == MilestoneState.active) return m;
    }
    for (final m in milestones) {
      if (m.state != MilestoneState.completed) return m;
    }
    return milestones.isEmpty ? null : milestones.last;
  }

  factory Roadmap.fromRow(Map<String, dynamic> row) {
    final path = row['career_paths'];
    final rawMilestones = (row['roadmap_milestones'] as List?) ?? const [];
    final milestones =
        rawMilestones
            .cast<Map<String, dynamic>>()
            .map(RoadmapMilestone.fromRow)
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return Roadmap(
      id: row['id'] as String,
      title: row['title'] as String,
      pathId: row['path_id'] as String?,
      pathSlug: path is Map<String, dynamic> ? path['slug'] as String? : null,
      milestones: milestones,
      skippedCount: (row['skipped_count'] as num?)?.toInt() ?? 0,
    );
  }
}
