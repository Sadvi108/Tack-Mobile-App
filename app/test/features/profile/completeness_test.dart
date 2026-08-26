import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/profile/application/completeness.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_sections.dart';

ProfileEntry entry(String id) => ProfileEntry(id: id, title: id);

Map<ProfileSection, List<ProfileEntry>> filled([
  Set<ProfileSection> empty = const {},
]) => {
  for (final section in ProfileSection.values)
    section: empty.contains(section) ? const [] : [entry('a')],
};

Profile undergraduate() => Profile(
  id: 'u1',
  fullName: 'Rafiq Hossain',
  countryId: 'bd',
  cityId: 'dhaka',
  phone: '+8801712345678',
  stage: EducationStage.bachelors,
  yearOfStudy: 4,
  yearsTotal: 4,
  mode: YearMode.launch,
  targetRole: 'Frontend developer',
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

Profile schoolStudent() => Profile(
  id: 'u2',
  fullName: 'Nusrat Jahan',
  countryId: 'bd',
  cityId: 'dhaka',
  phone: '+8801712345678',
  stage: EducationStage.highSchool,
  mode: YearMode.discover,
  intendedField: 'Computer science',
  onboardingCompletedAt: DateTime(2026, 1, 1),
);

void main() {
  group('an empty profile', () {
    test('is zero per cent and lists everything', () {
      final result = computeCompleteness(
        profile: const Profile(id: 'u1'),
        sections: const {},
        skillCount: 0,
      );
      expect(result.percent, 0);
      expect(result.isComplete, isFalse);
      expect(result.missing, isNotEmpty);
    });
  });

  group('what is asked depends on the stage', () {
    test(
      'a school student is never asked for an internship or a job title',
      () {
        final result = computeCompleteness(
          profile: schoolStudent(),
          sections: filled(),
          skillCount: 0,
        );

        // Counting these against a sixteen-year-old would leave their profile
        // permanently incomplete for questions nobody asked them.
        expect(result.missing, isNot(contains('add an internship or job')));
        expect(result.missing, isNot(contains('pick a target role')));
        expect(result.missing, isNot(contains('add a few more skills')));
        expect(result.percent, 100);
      },
    );

    test('a school student is asked about subjects and what they enjoy', () {
      final result = computeCompleteness(
        profile: schoolStudent(),
        sections: filled({ProfileSection.favourites, ProfileSection.hobbies}),
        skillCount: 0,
      );
      expect(result.missing, contains('add your favourite subjects'));
      expect(result.missing, contains('add what you do outside class'));
    });

    test('an undergraduate is asked for skills and a target role', () {
      final result = computeCompleteness(
        profile: undergraduate(),
        sections: filled(),
        skillCount: 8,
      );
      expect(result.percent, 100);
      expect(result.missing, isEmpty);

      final thin = computeCompleteness(
        profile: undergraduate().copyWith(targetRole: null),
        sections: filled(),
        skillCount: 2,
      );
      expect(thin.missing, contains('add a few more skills'));
    });

    test('an undergraduate is never asked what they want to study', () {
      final result = computeCompleteness(
        profile: undergraduate(),
        sections: filled({ProfileSection.favourites}),
        skillCount: 8,
      );
      expect(result.missing, isNot(contains('say what you want to study')));
    });
  });

  group('the banner', () {
    test('names two things rather than only a percentage', () {
      final result = computeCompleteness(
        profile: undergraduate(),
        sections: filled({
          ProfileSection.projects,
          ProfileSection.certifications,
        }),
        skillCount: 8,
      );
      expect(result.topTwo, hasLength(2));
      expect(result.sentence, startsWith('Two things left'));
      expect(result.sentence, contains('add a project'));
    });

    test('one thing left reads as one thing', () {
      final result = computeCompleteness(
        profile: undergraduate(),
        sections: filled({ProfileSection.portfolio}),
        skillCount: 8,
      );
      expect(result.missing, hasLength(1));
      expect(result.sentence, 'One thing left: add your GitHub or LinkedIn.');
    });

    test('a complete profile says so', () {
      final result = computeCompleteness(
        profile: undergraduate(),
        sections: filled(),
        skillCount: 8,
      );
      expect(result.sentence, 'Your profile is complete.');
    });
  });

  test('country is asked for, now that the app is not Bangladesh-only', () {
    final result = computeCompleteness(
      profile: undergraduate().copyWith(countryId: null),
      sections: filled(),
      skillCount: 8,
    );
    // copyWith cannot clear a field, so this checks the check exists at all.
    expect(
      computeCompleteness(
        profile: const Profile(id: 'u1'),
        sections: const {},
        skillCount: 0,
      ).missing,
      contains('add your country'),
    );
    expect(result.percent, greaterThan(0));
  });

  test('no missing item is phrased as a criticism', () {
    for (final profile in [const Profile(id: 'u1'), schoolStudent()]) {
      final result = computeCompleteness(
        profile: profile,
        sections: const {},
        skillCount: 0,
      );
      for (final item in result.missing) {
        expect(
          item.split(' ').first,
          anyOf('add', 'say', 'pick'),
          reason: '"$item" should be an instruction, not a judgement',
        );
      }
    }
  });

  group('section health', () {
    test('nothing reads as empty, some as thin, enough as good', () {
      expect(healthFor(ProfileSection.favourites, 0), SectionHealth.empty);
      expect(healthFor(ProfileSection.favourites, 1), SectionHealth.thin);
      expect(healthFor(ProfileSection.favourites, 3), SectionHealth.good);
      expect(healthFor(ProfileSection.hobbies, 2), SectionHealth.good);
    });
  });

  group('which sections each stage sees', () {
    test('a school student sees subjects and hobbies, not courses', () {
      final sections = ProfileSection.forSchool();
      expect(sections, contains(ProfileSection.favourites));
      expect(sections, contains(ProfileSection.hobbies));
      expect(sections, isNot(contains(ProfileSection.courses)));
      expect(sections, isNot(contains(ProfileSection.experience)));
    });

    test('an undergraduate sees courses and experience, not hobbies', () {
      final sections = ProfileSection.forUniversity();
      expect(sections, contains(ProfileSection.courses));
      expect(sections, contains(ProfileSection.experience));
      expect(sections, isNot(contains(ProfileSection.hobbies)));
    });
  });
}
