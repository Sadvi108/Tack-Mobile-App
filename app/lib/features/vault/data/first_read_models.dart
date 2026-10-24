/// A CV first read: three readers' verdicts on one version of a CV, as the
/// worker stored them (`cv_first_reads`, 0084). Everything a reader
/// "remembers" has already been checked against the CV's own words.
class ReadChunk {
  const ReadChunk(this.index, this.section);
  final int index;
  final String section;
}

class ReaderVerdict {
  const ReaderVerdict({
    required this.persona,
    required this.needle,
    required this.quitChunk,
    required this.sayback,
    required this.remembered,
    required this.oneAction,
  });

  final String persona;

  /// Interest per chunk, -2 (about to stop) to +2 (leaning in).
  final Map<int, int> needle;

  /// The chunk they stopped at, or 0 for read to the end.
  final int quitChunk;
  final String sayback;
  final List<String> remembered;
  final String oneAction;

  static const _names = {
    'recruiter': 'A recruiter with eight seconds',
    'hiring_manager': 'The hiring manager',
    'hr_officer': 'An HR officer',
  };

  String get name => _names[persona]!;

  int interest(int chunk) => needle[chunk] ?? 0;

  static ReaderVerdict? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final persona = raw['persona'];
    final sayback = raw['sayback'];
    final oneAction = raw['one_action'];
    if (persona is! String || !_names.containsKey(persona)) return null;
    if (sayback is! String || oneAction is! String) return null;
    final needle = <int, int>{};
    for (final n in raw['needle'] is List ? raw['needle'] as List : const []) {
      if (n is Map && n['chunk'] is int && n['value'] is num) {
        needle[n['chunk'] as int] = (n['value'] as num).round().clamp(-2, 2);
      }
    }
    final remembered = raw['remembered'];
    return ReaderVerdict(
      persona: persona,
      needle: needle,
      quitChunk: raw['quit_chunk'] is int ? raw['quit_chunk'] as int : 0,
      sayback: sayback,
      remembered: [
        if (remembered is List)
          for (final r in remembered)
            if (r is String) r,
      ],
      oneAction: oneAction,
    );
  }
}

class FirstRead {
  const FirstRead({required this.chunks, required this.readers});

  final List<ReadChunk> chunks;
  final List<ReaderVerdict> readers;

  /// The section a reader stopped in, or null if they read it all.
  String? stoppedAt(ReaderVerdict reader) {
    if (reader.quitChunk == 0) return null;
    for (final c in chunks) {
      if (c.index == reader.quitChunk) return c.section;
    }
    return null;
  }

  static FirstRead? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chunks = [
      if (raw['chunks'] is List)
        for (final c in raw['chunks'] as List)
          if (c is Map && c['index'] is int && c['section'] is String)
            ReadChunk(c['index'] as int, c['section'] as String),
    ];
    final readers = [
      if (raw['readers'] is List)
        for (final r in raw['readers'] as List) ?ReaderVerdict.fromJson(r),
    ];
    if (chunks.isEmpty || readers.isEmpty) return null;
    return FirstRead(chunks: chunks, readers: readers);
  }
}
