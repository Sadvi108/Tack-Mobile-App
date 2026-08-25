/// What the analyser pulled out of a job description.
class JdAnalysis {
  const JdAnalysis({
    required this.analysisId,
    required this.jobTitle,
    required this.skills,
    required this.qualifications,
    required this.responsibilities,
    this.seniority,
    this.experience,
  });

  final String analysisId;
  final String jobTitle;
  final List<String> skills;
  final List<String> qualifications;
  final List<String> responsibilities;
  final String? seniority;
  final String? experience;

  factory JdAnalysis.fromJson(String id, Map<String, dynamic> json) => JdAnalysis(
        analysisId: id,
        jobTitle: (json['job_title'] as String?) ?? 'This role',
        skills: (json['skills'] as List?)?.cast<String>() ?? const [],
        qualifications: (json['qualifications'] as List?)?.cast<String>() ?? const [],
        responsibilities: (json['responsibilities'] as List?)?.cast<String>() ?? const [],
        seniority: json['seniority'] as String?,
        experience: json['experience'] as String?,
      );
}

/// How the student measures up. Computed by set comparison on the server, so
/// the same description always gives the same number.
class JdMatch {
  const JdMatch({
    required this.matchPercent,
    required this.matched,
    required this.missing,
  });

  final int matchPercent;
  final List<String> matched;
  final List<String> missing;

  static const empty = JdMatch(matchPercent: 0, matched: [], missing: []);

  factory JdMatch.fromJson(Map<String, dynamic> json) => JdMatch(
        matchPercent: (json['matchPercent'] as num?)?.toInt() ??
            (json['match_percent'] as num?)?.toInt() ??
            0,
        matched: (json['matched'] as List?)?.cast<String>() ??
            (json['matched_skills'] as List?)?.cast<String>() ??
            const [],
        missing: (json['missing'] as List?)?.cast<String>() ??
            (json['missing_skills'] as List?)?.cast<String>() ??
            const [],
      );
}

/// The state of one analysis run.
sealed class AnalysisState {
  const AnalysisState();
}

class AnalysisIdle extends AnalysisState {
  const AnalysisIdle();
}

class AnalysisQueued extends AnalysisState {
  const AnalysisQueued(this.jobId);
  final String? jobId;
}

class AnalysisReady extends AnalysisState {
  const AnalysisReady(this.analysis, this.match, {this.cached = false});
  final JdAnalysis analysis;
  final JdMatch match;
  final bool cached;
}

class AnalysisFailed extends AnalysisState {
  const AnalysisFailed(this.message, {this.quotaExhausted = false});
  final String message;
  final bool quotaExhausted;
}
