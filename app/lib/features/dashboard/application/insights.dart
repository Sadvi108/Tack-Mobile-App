import '../../../design/tack.dart';
import '../../profile/data/profile.dart';
import '../data/dashboard_feed.dart';

/// How an insight should feel, which decides its colour and nothing else.
enum InsightTone {
  /// Something has a date on it and that date has passed or is today.
  urgent,

  /// The student did something worth noticing. Never manufactured — if there
  /// is nothing to be pleased about, no positive card is produced.
  positive,

  /// A specific, small thing that would move the score.
  opportunity,

  /// Context. Neither good nor bad.
  neutral,
}

/// One card in the suggestion deck.
///
/// The deck is the answer to "what should I be doing", and every card in it is
/// derived from something the student entered — there is no model involved and
/// nothing is invented. A card that cannot be justified from the feed is not
/// built at all, which is why an empty deck is a legitimate result.
class Insight {
  const Insight({
    required this.id,
    required this.label,
    required this.title,
    required this.body,
    required this.tone,
    this.ctaLabel,
    this.route,
  });

  /// Stable across rebuilds, so the deck does not reshuffle under a thumb and
  /// so analytics can count a card without naming its contents.
  final String id;

  /// The small mono chip at the top of the card.
  final String label;

  final String title;
  final String body;
  final InsightTone tone;
  final String? ctaLabel;
  final String? route;
}

/// Builds the suggestion deck from one feed snapshot.
///
/// Ordering is by what the student cannot afford to miss, not by what is
/// easiest to render: dates that have passed, then dates that are today, then
/// momentum, then the biggest available win.
///
/// Year mode is a hard filter, not a tone. A first-year is never shown a
/// deadline, an application or the word "apply" — that is the whole product
/// argument, and it is enforced here rather than trusted to the copy.
List<Insight> buildInsights(DashboardFeed feed, {int limit = 5}) {
  final mode = feed.mode;
  final talksAboutJobs = mode.showsFunnel || mode == YearMode.prove;
  final today = feed.today;
  final cards = <Insight>[];

  // ---------------------------------------------------------------- overdue
  final overdue = feed.overdue.where((e) => _allowed(e.kind, mode)).toList();
  if (overdue.isNotEmpty) {
    final first = overdue.first;
    cards.add(
      Insight(
        id: 'overdue',
        label: 'BEHIND',
        title: overdue.length == 1
            ? first.title
            : '${overdue.length} things slipped past',
        body: overdue.length == 1
            ? '${_whenItWasDue(first, today)} Move the date or tick it off — either is fine.'
            : 'They are still worth doing. Start with the oldest and the rest will feel smaller.',
        tone: InsightTone.urgent,
        ctaLabel: 'Take a look',
        route: overdue.length == 1 ? first.route : '/roadmap',
      ),
    );
  }

  // ------------------------------------------------------------------ today
  final dueToday = feed.upcoming
      .where((e) => e.daysFrom(today) == 0 && _allowed(e.kind, mode))
      .toList();
  if (dueToday.isNotEmpty) {
    cards.add(
      Insight(
        id: 'due-today',
        label: 'TODAY',
        title: dueToday.length == 1
            ? dueToday.first.title
            : '${dueToday.length} things are set for today',
        body: dueToday.length == 1
            ? (dueToday.first.subtitle ?? 'Set for today.')
            : 'A short list. Doing one of them still counts.',
        tone: InsightTone.urgent,
        ctaLabel: 'Open it',
        route: dueToday.first.route,
      ),
    );
  }

  // ----------------------------------------------------------------- streak
  final streak = feed.streak;
  if (streak.current >= 3) {
    cards.add(
      Insight(
        id: 'streak',
        label: 'STREAK',
        title: '${streak.current} days in a row',
        body: streak.isPersonalBest
            ? 'This is the longest run you have had. One small thing today keeps it.'
            : 'Your best is ${streak.longest} days. You are ${streak.longest - streak.current} off it.',
        tone: InsightTone.positive,
      ),
    );
  } else if (streak.current == 0 && streak.longest >= 3) {
    cards.add(
      Insight(
        id: 'streak-restart',
        label: 'STREAK',
        title: 'Your best run was ${streak.longest} days',
        body:
            'Streaks break. Ticking one thing today starts a new one, and day one counts the same as day nine.',
        tone: InsightTone.neutral,
      ),
    );
  }

  // --------------------------------------------------------------- momentum
  final now = feed.thisWeek;
  final before = feed.lastWeek;
  if (now.moves > 0 && now.moves > before.moves) {
    cards.add(
      Insight(
        id: 'momentum-up',
        label: 'THIS WEEK',
        title: 'A busier week than last',
        body: _movesSentence(now, before, mode),
        tone: InsightTone.positive,
      ),
    );
  } else if (now.isQuiet && !before.isQuiet) {
    cards.add(
      Insight(
        id: 'momentum-quiet',
        label: 'THIS WEEK',
        title: 'A quiet week so far',
        body:
            'Last week you got through ${before.moves} ${before.moves == 1 ? 'thing' : 'things'}. '
            'One small step puts this week back on the board.',
        tone: InsightTone.neutral,
      ),
    );
  }

  // ------------------------------------------------------------ set-up gaps
  if (!feed.hasCv) {
    cards.add(
      const Insight(
        id: 'no-cv',
        label: 'MISSING',
        title: 'Tack has not seen your CV',
        body:
            'Upload it and Tack reads it for you — the skills it finds fill in your profile and your score.',
        tone: InsightTone.opportunity,
        ctaLabel: 'Add your CV',
        route: '/vault',
      ),
    );
  }

  if (feed.chosenPaths == 0) {
    cards.add(
      Insight(
        id: 'no-path',
        label: 'NEXT',
        title: mode.isAtSchool
            ? 'Pick something to aim at'
            : 'Choose a target job',
        body:
            'Everything else builds from it: your roadmap, the skills worth learning, and what your score is measured against.',
        tone: InsightTone.opportunity,
        ctaLabel: 'Explore paths',
        route: '/paths',
      ),
    );
  }

  // -------------------------------------------------------------- skill gap
  final core = feed.skillGap.where((s) => s.isCore).toList();
  if (core.isNotEmpty && feed.primaryPathTitle != null) {
    final named = core.take(3).map((s) => s.name).join(', ');
    cards.add(
      Insight(
        id: 'skill-gap',
        label: 'SKILLS',
        title: core.length == 1
            ? '${core.first.name} is the gap'
            : '${core.length} core skills to go',
        body:
            '${feed.primaryPathTitle} asks for $named. Learning one and adding it here moves your score and your match.',
        tone: InsightTone.opportunity,
        ctaLabel: 'See the path',
        route: feed.primaryPathSlug == null
            ? '/paths'
            : '/paths/${feed.primaryPathSlug}',
      ),
    );
  }

  // ---------------------------------------------------------- next roadmap
  final roadmap = feed.roadmap;
  if (roadmap.nextTaskTitle != null && overdue.isEmpty) {
    cards.add(
      Insight(
        id: 'next-task',
        label: 'ROADMAP',
        title: roadmap.nextTaskTitle!,
        body: [
          if (roadmap.activeMilestone != null) roadmap.activeMilestone!,
          if (roadmap.nextTaskMinutes != null)
            'about ${roadmap.nextTaskMinutes} minutes',
          if (roadmap.nextTaskPoints > 0) '+${roadmap.nextTaskPoints} points',
        ].join(' · '),
        tone: InsightTone.opportunity,
        ctaLabel: 'Open the roadmap',
        route: '/roadmap',
      ),
    );
  }

  // ------------------------------------------------------- job hunt health
  // Only ever for someone actually job hunting. A third-year is told to
  // practise; nobody junior is told anything about applying.
  if (talksAboutJobs && feed.counts.total > 0) {
    final applied = feed.counts[TackStatus.applied];
    final interviews = feed.counts[TackStatus.interview];
    if (applied >= 5 && interviews == 0) {
      cards.add(
        const Insight(
          id: 'no-callbacks',
          label: 'CV',
          title: 'Plenty sent, nothing back yet',
          body:
              'That usually points at the CV rather than at you. Have Tack score it and fix the two things it flags.',
          tone: InsightTone.opportunity,
          ctaLabel: 'Check my CV',
          route: '/vault',
        ),
      );
    }
  }

  return cards.take(limit).toList(growable: false);
}

/// When something was due, as a sentence.
///
/// [TimelineEntry.relativeTo] answers "how late is this" — "2 days late" — which
/// is right on a list row and wrong in a sentence: "this was due 2 days late"
/// is not English. Past tense needs its own phrasing.
String _whenItWasDue(TimelineEntry entry, DateTime today) {
  final days = entry.daysFrom(today);
  if (days == 0) return 'This is due today.';
  if (days == -1) return 'This was due yesterday.';
  return 'This was due ${-days} days ago.';
}

/// Which timeline kinds a mode is allowed to hear about at all.
bool _allowed(TimelineKind kind, YearMode mode) {
  if (kind == TimelineKind.task) return true;
  return mode.showsFunnel || mode == YearMode.prove;
}

String _movesSentence(WeekSummary now, WeekSummary before, YearMode mode) {
  final parts = <String>[
    if (now.tasksDone > 0)
      '${now.tasksDone} roadmap ${now.tasksDone == 1 ? 'step' : 'steps'}',
    if (now.skillsAdded > 0)
      '${now.skillsAdded} ${now.skillsAdded == 1 ? 'skill' : 'skills'}',
    if (now.projectsAdded > 0)
      '${now.projectsAdded} ${now.projectsAdded == 1 ? 'project' : 'projects'}',
    if (now.documentsAdded > 0)
      '${now.documentsAdded} ${now.documentsAdded == 1 ? 'document' : 'documents'}',
    if (now.interviewsPractised > 0)
      '${now.interviewsPractised} practice ${now.interviewsPractised == 1 ? 'session' : 'sessions'}',
    // Never counted out loud for a junior year, even when the number is real.
    if (now.applicationsAdded > 0 && mode.showsFunnel)
      '${now.applicationsAdded} sent',
  ];
  final done = parts.isEmpty
      ? '${now.moves} ${now.moves == 1 ? 'thing' : 'things'}'
      : parts.length == 1
      ? parts.first
      : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  return before.isQuiet
      ? 'You got through $done. Last week had nothing on it.'
      : 'You got through $done, against ${before.moves} last week.';
}
