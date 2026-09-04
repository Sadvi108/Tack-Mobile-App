import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';

/// Everything Tack knows about the student, as `my_profile_document()` returns
/// it.
///
/// Parsed rather than passed around as a raw map so that a missing field is a
/// compile error here instead of a blank line on somebody's CV.
class ProfileDocument {
  const ProfileDocument({
    required this.identity,
    this.education = const [],
    this.experiences = const [],
    this.projects = const [],
    this.certifications = const [],
    this.skills = const [],
    this.activities = const [],
    this.links = const [],
  });

  final Identity identity;
  final List<Education> education;
  final List<Experience> experiences;
  final List<Project> projects;
  final List<Certification> certifications;
  final List<Skill> skills;
  final List<Activity> activities;
  final List<PortfolioLink> links;

  /// Whether there is enough here to be worth putting on a page.
  ///
  /// A name alone is not a CV. Used to decide between the builder and the
  /// "add these first" empty state, because handing somebody a PDF containing
  /// only their own name is worse than telling them what is missing.
  bool get hasSubstance =>
      education.isNotEmpty ||
      experiences.isNotEmpty ||
      projects.isNotEmpty ||
      certifications.isNotEmpty ||
      skills.isNotEmpty ||
      activities.isNotEmpty;

  /// What a student would have to add to make the CV worth exporting, in the
  /// order that adds the most.
  List<String> get whatIsMissing => [
    if (education.isEmpty) 'where you study',
    if (skills.isEmpty) 'a few skills',
    if (projects.isEmpty && experiences.isEmpty) 'a project or a job',
  ];

  int countFor(CvSection section) => switch (section) {
    CvSection.experiences => experiences.length,
    CvSection.projects => projects.length,
    CvSection.education => education.length,
    CvSection.skills => skills.length,
    CvSection.certifications => certifications.length,
    CvSection.activities => activities.length,
  };

  factory ProfileDocument.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        ((json[key] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(parse)
            .toList(growable: false);

    return ProfileDocument(
      identity: Identity.fromJson(
        (json['identity'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      education: list('education', Education.fromJson),
      experiences: list('experiences', Experience.fromJson),
      projects: list('projects', Project.fromJson),
      certifications: list('certifications', Certification.fromJson),
      skills: list('skills', Skill.fromJson),
      activities: list('activities', Activity.fromJson),
      links: list('links', PortfolioLink.fromJson),
    );
  }
}

class Identity {
  const Identity({
    this.fullName,
    this.city,
    this.country,
    this.phone,
    this.headline,
  });

  final String? fullName;
  final String? city;
  final String? country;

  /// Printed on the CV, never on the public page. The filtering happens
  /// server-side; this field exists so the CV renderer has it.
  final String? phone;
  final String? headline;

  String? get whereTheyAre => switch ((city, country)) {
    (final c?, final co?) => '$c, $co',
    (final c?, null) => c,
    (null, final co?) => co,
    _ => null,
  };

  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
    fullName: json['full_name'] as String?,
    city: json['city'] as String?,
    country: json['country'] as String?,
    phone: json['phone'] as String?,
    headline: json['headline'] as String?,
  );
}

class Education {
  const Education({
    this.institution,
    this.degree,
    this.fieldOfStudy,
    this.startYear,
    this.graduationYear,
    this.cgpa,
    this.cgpaScale,
    this.isCurrent = false,
  });

  final String? institution;
  final String? degree;
  final String? fieldOfStudy;
  final int? startYear;
  final int? graduationYear;
  final double? cgpa;
  final double? cgpaScale;
  final bool isCurrent;

  /// "BSc in Computer Science", or whichever half exists.
  String? get line => switch ((degree, fieldOfStudy)) {
    (final d?, final f?) => '$d in $f',
    (final d?, null) => d,
    (null, final f?) => f,
    _ => null,
  };

  String? get years => switch ((startYear, graduationYear)) {
    (final s?, final g?) => '$s – $g',
    (null, final g?) => isCurrent ? 'expected $g' : '$g',
    (final s?, null) => '$s – ',
    _ => null,
  };

  /// Only shown when it helps. Below 3.0 on a 4-point scale, a CGPA is not
  /// doing the student any favours and the space is better spent.
  String? get cgpaLabel {
    final value = cgpa;
    final scale = cgpaScale;
    if (value == null || scale == null || scale == 0) return null;
    if (value / scale < 0.75) return null;
    return 'CGPA ${value.toStringAsFixed(2)} / ${scale.toStringAsFixed(1)}';
  }

  factory Education.fromJson(Map<String, dynamic> json) => Education(
    institution: json['institution'] as String?,
    degree: json['degree'] as String?,
    fieldOfStudy: json['field_of_study'] as String?,
    startYear: (json['start_year'] as num?)?.toInt(),
    graduationYear: (json['graduation_year'] as num?)?.toInt(),
    cgpa: (json['cgpa'] as num?)?.toDouble(),
    cgpaScale: (json['cgpa_scale'] as num?)?.toDouble(),
    isCurrent: json['is_current'] as bool? ?? false,
  );
}

class Experience {
  const Experience({
    this.company,
    this.title,
    this.location,
    this.startDate,
    this.endDate,
    this.isCurrent = false,
    this.description,
  });

  final String? company;
  final String? title;
  final String? location;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final String? description;

  factory Experience.fromJson(Map<String, dynamic> json) => Experience(
    company: json['company'] as String?,
    title: json['title'] as String?,
    location: json['location'] as String?,
    startDate: DateTime.tryParse('${json['start_date']}'),
    endDate: DateTime.tryParse('${json['end_date']}'),
    isCurrent: json['is_current'] as bool? ?? false,
    description: json['description'] as String?,
  );
}

class Project {
  const Project({
    this.id,
    this.title,
    this.summary,
    this.url,
    this.repoUrl,
    this.completedOn,
  });

  final String? id;
  final String? title;
  final String? summary;
  final String? url;
  final String? repoUrl;
  final DateTime? completedOn;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String?,
    title: json['title'] as String?,
    summary: json['summary'] as String?,
    url: json['url'] as String?,
    repoUrl: json['repo_url'] as String?,
    completedOn: DateTime.tryParse('${json['completed_on']}'),
  );
}

class Certification {
  const Certification({this.title, this.issuer, this.issuedOn});

  final String? title;
  final String? issuer;
  final DateTime? issuedOn;

  factory Certification.fromJson(Map<String, dynamic> json) => Certification(
    title: json['title'] as String?,
    issuer: json['issuer'] as String?,
    issuedOn: DateTime.tryParse('${json['issued_on']}'),
  );
}

class Skill {
  const Skill({required this.name, this.category, this.proficiency});

  final String name;
  final String? category;
  final int? proficiency;

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
    name: (json['name'] as String?) ?? '',
    category: json['category'] as String?,
    proficiency: (json['proficiency'] as num?)?.toInt(),
  );
}

class Activity {
  const Activity({this.title, this.organisation, this.role, this.category});

  final String? title;
  final String? organisation;
  final String? role;
  final String? category;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    title: json['title'] as String?,
    organisation: json['organisation'] as String?,
    role: json['role'] as String?,
    category: json['category'] as String?,
  );
}

class PortfolioLink {
  const PortfolioLink({required this.kind, required this.url});

  final String kind;
  final String url;

  factory PortfolioLink.fromJson(Map<String, dynamic> json) => PortfolioLink(
    kind: (json['kind'] as String?) ?? 'link',
    url: (json['url'] as String?) ?? '',
  );
}

/// The sections a CV can carry, in the order they appear by default.
///
/// Experience first, then proof of work, then where you studied. A student
/// with a job leads with it; one without leads with what they have built,
/// which for a Bangladeshi undergraduate is usually the stronger card.
enum CvSection {
  experiences,
  projects,
  education,
  skills,
  certifications,
  activities;

  static CvSection? fromWire(String value) =>
      CvSection.values.where((s) => s.name == value).firstOrNull;

  String get heading => switch (this) {
    CvSection.experiences => 'Experience',
    CvSection.projects => 'Projects',
    CvSection.education => 'Education',
    CvSection.skills => 'Skills',
    CvSection.certifications => 'Certifications',
    CvSection.activities => 'Activities',
  };
}

/// Which sections the student shows, and in what order.
class CvLayout {
  const CvLayout({this.sections = defaultSections});

  final List<CvSection> sections;

  static const defaultSections = [
    CvSection.experiences,
    CvSection.projects,
    CvSection.education,
    CvSection.skills,
    CvSection.certifications,
    CvSection.activities,
  ];

  /// Sections not currently shown, so the editor can offer them back.
  List<CvSection> get hidden =>
      CvSection.values.where((s) => !sections.contains(s)).toList();

  CvLayout withSections(List<CvSection> next) => CvLayout(sections: next);

  factory CvLayout.fromRow(Map<String, dynamic>? row) {
    final raw = (row?['sections'] as List?)?.cast<String>();
    if (raw == null) return const CvLayout();
    final parsed = raw.map(CvSection.fromWire).nonNulls.toList();
    // An empty or unrecognised layout falls back rather than rendering a blank
    // page — a stored value from an older build must never cost somebody their
    // CV.
    return parsed.isEmpty ? const CvLayout() : CvLayout(sections: parsed);
  }

  List<String> toWire() => [for (final s in sections) s.name];
}

class CvBuilderRepository {
  const CvBuilderRepository(this._db);

  final SupabaseClient _db;

  Future<ProfileDocument> document() async {
    try {
      final row = await _db.rpc<Map<String, dynamic>>('my_profile_document');
      return ProfileDocument.fromJson(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<CvLayout> layout() async {
    try {
      final rows = await _db.from('cv_layouts').select('sections').limit(1);
      return CvLayout.fromRow(rows.isEmpty ? null : rows.first);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> saveLayout(CvLayout layout) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw const Failure('You are signed out. Log in and try again.');
    }
    try {
      await _db.from('cv_layouts').upsert({
        'user_id': userId,
        'sections': layout.toWire(),
      }, onConflict: 'user_id');
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final cvBuilderRepositoryProvider = Provider<CvBuilderRepository>(
  (ref) => CvBuilderRepository(ref.watch(supabaseProvider)),
);

final profileDocumentProvider = FutureProvider<ProfileDocument>(
  (ref) => ref.watch(cvBuilderRepositoryProvider).document(),
);

final cvLayoutProvider = FutureProvider<CvLayout>(
  (ref) => ref.watch(cvBuilderRepositoryProvider).layout(),
);
