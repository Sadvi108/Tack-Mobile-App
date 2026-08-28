import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/onboarding/domain/derive_mode.dart';
import 'package:tack/features/profile/data/education_stage.dart';
import 'package:tack/features/profile/data/profile.dart';

void main() {
  // The matrix is generated against the live database. The app previews a mode
  // while a student is still choosing, and the server stores what it computes
  // itself — if the two ever disagree the app promises one thing and delivers
  // another, so all 288 combinations are checked rather than a handful.
  test('agrees with the database across every combination', () {
    final rows =
        (jsonDecode(
                  File(
                    'test/features/onboarding/sql_mode_matrix.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>();

    expect(rows, hasLength(288));

    // The fixture was generated with a June graduation month.
    final now = DateTime(2026, 8);
    final disagreements = <String>[];

    for (final row in rows) {
      final stage = EducationStage.fromWire(row['stage'] as String);
      final dart = deriveMode(
        stage: stage,
        yearOfStudy: row['year_of_study'] as int?,
        yearsTotal: row['years_total'] as int?,
        graduationYear: row['graduation_year'] as int?,
        graduationMonth: 6,
        now: now,
      );
      final sql = row['mode'] as String;
      if (dart.name != sql) {
        disagreements.add(
          '${row['stage']} y=${row['year_of_study']} of ${row['years_total']} '
          'grad=${row['graduation_year']}: sql=$sql dart=${dart.name}',
        );
      }
    }

    expect(disagreements, isEmpty);
  });

  group('the cases the architecture doc calls out', () {
    test('year 4 of a 4-year degree is launch', () {
      expect(
        deriveMode(
          stage: EducationStage.bachelors,
          yearOfStudy: 4,
          yearsTotal: 4,
        ),
        YearMode.launch,
      );
    });

    test('year 4 of a 5-year degree is still prove', () {
      // Medicine and architecture run five years; treating year four as final
      // would tell a student to start applying a year early.
      expect(
        deriveMode(
          stage: EducationStage.bachelors,
          yearOfStudy: 4,
          yearsTotal: 5,
        ),
        YearMode.prove,
      );
    });

    test('a graduation date in the past wins over the stated stage', () {
      // People finish and never update the dropdown.
      expect(
        deriveMode(
          stage: EducationStage.bachelors,
          yearOfStudy: 2,
          yearsTotal: 4,
          graduationYear: 2020,
          now: DateTime(2026, 8),
        ),
        YearMode.launch,
      );
    });

    test('a graduation date in the future does not', () {
      expect(
        deriveMode(
          stage: EducationStage.bachelors,
          yearOfStudy: 2,
          yearsTotal: 4,
          graduationYear: 2030,
          now: DateTime(2026, 8),
        ),
        YearMode.build,
      );
    });

    test('high school is discover whatever else is set', () {
      expect(
        deriveMode(
          stage: EducationStage.highSchool,
          yearOfStudy: 4,
          yearsTotal: 4,
          graduationYear: 2020,
        ),
        YearMode.discover,
      );
    });

    test('graduated is launch', () {
      expect(deriveMode(stage: EducationStage.graduated), YearMode.launch);
    });

    test('an unanswered stage falls back to explore, not to a crash', () {
      expect(deriveMode(stage: null), YearMode.explore);
    });
  });

  group('the under-13 guard', () {
    test('twelve is under thirteen', () {
      expect(isUnderThirteen(birthYear: 2014, now: DateTime(2026, 8)), isTrue);
    });

    test('thirteen is not', () {
      expect(isUnderThirteen(birthYear: 2013, now: DateTime(2026, 8)), isFalse);
    });

    test('is generous by a year, because being wrong the other way holds a '
        'child\'s data', () {
      // Somebody born in December 2013 is still twelve in August 2026, and is
      // treated as thirteen. The opposite mistake is the one that matters.
      expect(isUnderThirteen(birthYear: 2013, now: DateTime(2026, 1)), isFalse);
    });

    test('no birth year is not a block', () {
      expect(isUnderThirteen(birthYear: null), isFalse);
    });

    test('the age band says the same thing', () {
      expect(AgeBand.under13.isUnderThirteen, isTrue);
      expect(AgeBand.from13to15.isUnderThirteen, isFalse);
    });
  });
}
