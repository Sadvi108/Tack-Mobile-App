/// What kind of opening a student is looking for.
///
/// One control, not two. "Remote or in person" and "internship or full time"
/// are different questions, but a student does not think of them that way —
/// they think "show me internships" — so the filter is a single row of chips
/// and the query underneath decides which column each one touches.
enum RadarFilter {
  all,
  remote,
  onsite,
  internship,
  partTime,
  contract,
  volunteer;

  String get label => switch (this) {
    RadarFilter.all => 'All',
    RadarFilter.remote => 'Remote',
    RadarFilter.onsite => 'In person',
    RadarFilter.internship => 'Internships',
    RadarFilter.partTime => 'Part time',
    RadarFilter.contract => 'Contract',
    RadarFilter.volunteer => 'Volunteer',
  };

  /// Where the work happens. Null when this filter does not care.
  ///
  /// Named `wantsRemote` rather than `remote` because `remote` is already one
  /// of the values of this enum.
  bool? get wantsRemote => switch (this) {
    RadarFilter.remote => true,
    RadarFilter.onsite => false,
    _ => null,
  };

  /// What kind of work it is, as `employment_kind` names it. Null when this
  /// filter does not care.
  String? get kind => switch (this) {
    RadarFilter.internship => 'internship',
    RadarFilter.partTime => 'part_time',
    RadarFilter.contract => 'contract',
    RadarFilter.volunteer => 'volunteer',
    _ => null,
  };

  /// The key this chip counts itself by in `radar_kinds()`.
  String get countKey => switch (this) {
    RadarFilter.all => 'all',
    RadarFilter.remote => 'remote',
    RadarFilter.onsite => 'onsite',
    RadarFilter.internship => 'internship',
    RadarFilter.partTime => 'part_time',
    RadarFilter.contract => 'contract',
    RadarFilter.volunteer => 'volunteer',
  };

  /// Said when a chip has nothing behind it, so an empty result reads as a
  /// fact about the boards rather than about the student.
  String get emptyReason => switch (this) {
    RadarFilter.volunteer =>
      'No board Tack reads publishes volunteer roles. They are listed by '
          'charities directly, and Tack cannot see them yet.',
    RadarFilter.internship =>
      'No internships on the boards right now. Try again in a day — they '
          'appear in bursts.',
    _ => 'Nothing of this kind is listed right now.',
  };
}
