enum RadarFilter {
  all,
  fullTime,
  internship,
  partTime,
  contract,
  volunteer;

  String get label => switch (this) {
    RadarFilter.all => 'All',
    RadarFilter.fullTime => 'Full time',
    RadarFilter.internship => 'Internships',
    RadarFilter.partTime => 'Part time',
    RadarFilter.contract => 'Contract',
    RadarFilter.volunteer => 'Volunteer',
  };

  /// What kind of work it is, as `employment_kind` names it. Null when this
  /// filter does not care.
  String? get kind => switch (this) {
    RadarFilter.fullTime => 'full_time',
    RadarFilter.internship => 'internship',
    RadarFilter.partTime => 'part_time',
    RadarFilter.contract => 'contract',
    RadarFilter.volunteer => 'volunteer',
    _ => null,
  };

  /// The key this chip counts itself by in `radar_kinds()`.
  String get countKey => switch (this) {
    RadarFilter.all => 'all',
    RadarFilter.fullTime => 'full_time',
    RadarFilter.internship => 'internship',
    RadarFilter.partTime => 'part_time',
    RadarFilter.contract => 'contract',
    RadarFilter.volunteer => 'volunteer',
  };

  /// Said when a chip has nothing behind it, so an empty result reads as a
  /// fact about the boards rather than about the student.
  String get emptyReason => switch (this) {
    RadarFilter.volunteer =>
      'Try another city or check charities directly for volunteer roles.',
    RadarFilter.internship =>
      'No internships on the boards right now. Try again in a day — they '
          'appear in bursts.',
    _ => 'Nothing of this kind is listed right now.',
  };
}

/// Independent of job type: an internship can also be in person.
enum RadarWorkplace {
  all,
  onsite,
  remote;

  String get label => switch (this) {
    all => 'All work',
    onsite => 'In person',
    remote => 'Remote',
  };

  bool? get remoteValue => switch (this) {
    all => null,
    onsite => false,
    remote => true,
  };
}
