import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/profile/application/completeness.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_sections.dart';

Profile emptyProfile() => const Profile(id: 'u1');

Profile fullProfile() => Profile(
      id: 'u1',
      fullName: 'Rafiq Hossain',
      cityId: 'c1',
      phone: '+8801712345678',
      yearOfStudy: 4,
      yearsTotal: 4,
      targetRole: 'Frontend developer',
      onboardingCompletedAt: DateTime(2026, 1, 1),
    );

ProfileEntry entry(String id) => ProfileEntry(id: id, title: id);

Map<ProfileSection, List<ProfileEntry>> allSections() => {
      for (final section in ProfileSection.values) section: [entry('a')],
    };

void main() {
  test('an empty profile is zero per cent and lists everything', () {
    final result = computeCompleteness(
      profile: emptyProfile(),
      sections: const {},
      skillCount: 0,
    );
    expect(result.percent, 0);
    expect(result.missing, hasLength(12));
    expect(result.isComplete, isFalse);
  });

  test('a complete profile is a hundred per cent and lists nothing', () {
    final result = computeCompleteness(
      profile: fullProfile(),
      sections: allSections(),
      skillCount: 8,
    );
    expect(result.percent, 100);
    expect(result.missing, isEmpty);
    expect(result.sentence, 'Your profile is complete.');
  });

  test('the banner names two things rather than only a percentage', () {
    // Naming what to do is the whole point: a bare percentage is a scolding.
    final result = computeCompleteness(
      profile: fullProfile(),
      sections: {
        ...allSections(),
        ProfileSection.projects: const [],
        ProfileSection.certifications: const [],
      },
      skillCount: 8,
    );
    expect(result.topTwo, hasLength(2));
    expect(result.sentence, contains('add a project'));
    expect(result.sentence, startsWith('Two things left'));
  });

  test('one thing left reads as one thing, not two', () {
    final result = computeCompleteness(
      profile: fullProfile(),
      sections: {...allSections(), ProfileSection.portfolio: const []},
      skillCount: 8,
    );
    expect(result.missing, hasLength(1));
    expect(result.sentence, 'One thing left: add your GitHub or LinkedIn.');
  });

  test('five skills is the bar, not one', () {
    final four = computeCompleteness(
      profile: fullProfile(),
      sections: allSections(),
      skillCount: 4,
    );
    expect(four.missing, contains('add a few more skills'));

    final five = computeCompleteness(
      profile: fullProfile(),
      sections: allSections(),
      skillCount: 5,
    );
    expect(five.missing, isEmpty);
  });

  test('no missing item is phrased as a criticism', () {
    final result = computeCompleteness(
      profile: emptyProfile(),
      sections: const {},
      skillCount: 0,
    );
    for (final item in result.missing) {
      expect(item.split(' ').first, anyOf('add', 'say', 'pick'),
          reason: '"$item" should be an instruction, not a judgement');
    }
  });

  group('section health', () {
    test('nothing at all reads as empty', () {
      expect(healthFor(ProfileSection.projects, 0), SectionHealth.empty);
    });

    test('some but not enough reads as thin', () {
      expect(healthFor(ProfileSection.skills, 3), SectionHealth.thin);
    });

    test('enough reads as good', () {
      expect(healthFor(ProfileSection.skills, 8), SectionHealth.good);
      expect(healthFor(ProfileSection.education, 1), SectionHealth.good);
    });
  });
}
