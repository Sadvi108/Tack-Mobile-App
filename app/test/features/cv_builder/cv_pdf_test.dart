import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/cv_builder/data/cv_pdf.dart';
import 'package:tack/features/cv_builder/data/profile_document.dart';

ProfileDocument doc({
  List<Experience> experiences = const [],
  List<Project> projects = const [],
  List<Education> education = const [],
  List<Skill> skills = const [],
  List<Certification> certifications = const [],
  List<Activity> activities = const [],
  String? phone = '+880 1711111111',
}) => ProfileDocument(
  identity: Identity(
    fullName: 'Rafiq Hossain',
    city: 'Dhaka',
    country: 'Bangladesh',
    phone: phone,
    headline: 'Backend developer',
  ),
  experiences: experiences,
  projects: projects,
  education: education,
  skills: skills,
  certifications: certifications,
  activities: activities,
);

/// A PDF is a container format; the text lands compressed, so asserting on
/// bytes is not possible without a parser. What can be asserted cheaply is
/// that it is a real PDF, that it is not empty, and that it grows and shrinks
/// with the content — which is what catches a section silently not rendering.
int _pages(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final matches = RegExp(r'/Type\s*/Page[^s]').allMatches(text);
  return matches.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a real PDF for a student with a history', () async {
    final bytes = await CvPdf.build(
      document: doc(
        education: [
          const Education(
            institution: 'BUET',
            degree: 'BSc',
            fieldOfStudy: 'Computer Science',
            startYear: 2022,
            graduationYear: 2026,
            cgpa: 3.6,
            cgpaScale: 4,
            isCurrent: true,
          ),
        ],
        experiences: [
          Experience(
            company: 'Pathao',
            title: 'Backend intern',
            startDate: DateTime(2025, 6),
            endDate: DateTime(2025, 9),
            description: 'Built the APIs behind the rider app.',
          ),
        ],
        skills: const [
          Skill(name: 'Python', proficiency: 4),
          Skill(name: 'PostgreSQL', proficiency: 3),
        ],
      ),
      layout: const CvLayout(),
    );

    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.take(5)),
      startsWith('%PDF'),
      reason: 'the output must actually be a PDF',
    );
    expect(_pages(bytes), greaterThanOrEqualTo(1));
  });

  test('a student with nothing still produces a valid page', () async {
    // The builder should not offer this — hasSubstance is false and the screen
    // shows what to add instead — but the renderer must not throw if it is
    // ever reached, because the one thing worse than a thin CV is a crash.
    final bytes = await CvPdf.build(document: doc(), layout: const CvLayout());
    expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF'));
  });

  test(
    'a long history runs to more than one page rather than truncating',
    () async {
      final many = [
        for (var i = 0; i < 24; i++)
          Experience(
            company: 'Company $i',
            title: 'Engineer $i',
            startDate: DateTime(2020 + (i % 5), 1),
            endDate: DateTime(2021 + (i % 5), 1),
            description:
                'A description long enough to take a couple of lines on the '
                'page, repeated so the document is forced past a single sheet '
                'of A4 and the flow has to do its job. Entry number $i.',
          ),
      ];

      final bytes = await CvPdf.build(
        document: doc(experiences: many),
        layout: const CvLayout(),
      );
      expect(
        _pages(bytes),
        greaterThan(1),
        reason: 'MultiPage must flow, not clip the overflow',
      );
    },
  );

  test('an empty section is dropped, not printed as a bare heading', () async {
    final withSkills = await CvPdf.build(
      document: doc(skills: const [Skill(name: 'Python')]),
      layout: const CvLayout(sections: [CvSection.skills]),
    );
    final without = await CvPdf.build(
      document: doc(),
      layout: const CvLayout(sections: [CvSection.skills]),
    );

    // A heading plus its rule is real content; the version with no skills must
    // be measurably smaller because it renders neither.
    expect(
      without.length,
      lessThan(withSkills.length),
      reason: 'an empty Skills section should render nothing at all',
    );
  });

  test('the layout decides what is rendered', () async {
    final full = await CvPdf.build(
      document: doc(
        skills: const [Skill(name: 'Python')],
        certifications: [
          Certification(
            title: 'AWS',
            issuer: 'Amazon',
            issuedOn: DateTime(2025),
          ),
        ],
      ),
      layout: const CvLayout(),
    );
    final trimmed = await CvPdf.build(
      document: doc(
        skills: const [Skill(name: 'Python')],
        certifications: [
          Certification(
            title: 'AWS',
            issuer: 'Amazon',
            issuedOn: DateTime(2025),
          ),
        ],
      ),
      layout: const CvLayout(sections: [CvSection.skills]),
    );

    expect(
      trimmed.length,
      lessThan(full.length),
      reason: 'hiding a section the student has data for must shrink the PDF',
    );
  });
}
