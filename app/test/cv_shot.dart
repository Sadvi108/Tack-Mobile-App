import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/cv_builder/data/cv_pdf.dart';
import 'package:tack/features/cv_builder/data/profile_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write a sample CV to look at', () async {
    final bytes = await CvPdf.build(
      document: ProfileDocument(
        identity: const Identity(
          fullName: 'Rafiq Hossain',
          city: 'Dhaka',
          country: 'Bangladesh',
          phone: '+880 1711111111',
          headline: 'Backend developer',
        ),
        links: const [
          PortfolioLink(kind: 'github', url: 'github.com/rafiq'),
        ],
        education: const [
          Education(
            institution: 'Bangladesh University of Engineering and Technology',
            degree: 'BSc', fieldOfStudy: 'Computer Science and Engineering',
            startYear: 2022, graduationYear: 2026,
            cgpa: 3.62, cgpaScale: 4, isCurrent: true,
          ),
        ],
        experiences: [
          Experience(
            company: 'Pathao', title: 'Backend intern',
            location: 'Dhaka',
            startDate: DateTime(2025, 6), endDate: DateTime(2025, 9),
            description:
                'Built and shipped three endpoints behind the rider app, and '
                'cut the slowest query on the trips table from 2.4s to 180ms.',
          ),
          Experience(
            company: 'BRAC IT', title: 'Junior developer (part time)',
            startDate: DateTime(2024, 7), endDate: DateTime(2025, 2),
            description: 'Maintained an internal reporting tool used by 40 staff.',
          ),
        ],
        projects: [
          Project(
            title: 'Dhaka bus tracker',
            summary:
                'Live arrival times for 12 routes, built with Flutter and a '
                'Postgres backend. Used by about 200 people a week.',
            repoUrl: 'github.com/rafiq/bus-tracker',
            completedOn: DateTime(2025, 12),
          ),
        ],
        certifications: [
          Certification(
            title: 'AWS Certified Cloud Practitioner',
            issuer: 'Amazon Web Services', issuedOn: DateTime(2025, 3),
          ),
        ],
        skills: const [
          Skill(name: 'Python', proficiency: 5),
          Skill(name: 'PostgreSQL', proficiency: 4),
          Skill(name: 'Django', proficiency: 4),
          Skill(name: 'Git', proficiency: 4),
          Skill(name: 'Docker', proficiency: 3),
          Skill(name: 'REST APIs', proficiency: 3),
        ],
        activities: const [
          Activity(
            title: 'BUET Computer Club', role: 'Events secretary',
            organisation: 'BUET', category: 'leadership',
          ),
        ],
      ),
      layout: const CvLayout(),
    );
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/cv.pdf').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  wrote build/shots/cv.pdf (${bytes.length} bytes)');
  });
}
