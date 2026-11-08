import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/coach/application/coach.dart';

void main() {
  test('every year gets four starters', () {
    for (final mode in YearMode.values) {
      expect(startersFor(mode).length, 4, reason: mode.name);
      expect(startersFor(mode).toSet().length, 4, reason: mode.name);
    }
  });

  test('no early year is asked about applying', () {
    final banned = RegExp(r'deadline|apply|application', caseSensitive: false);
    for (final mode in [YearMode.discover, YearMode.explore, YearMode.build]) {
      for (final q in startersFor(mode)) {
        expect(banned.hasMatch(q), isFalse, reason: '${mode.name}: $q');
      }
    }
  });

  test('every starter is sentence case', () {
    // Capital first; after that only an acronym (CV) may be capitalised.
    final word = RegExp(r"[A-Za-z']+");
    for (final mode in YearMode.values) {
      for (final q in startersFor(mode)) {
        final words = word.allMatches(q).map((m) => m.group(0)!).toList();
        expect(words.first[0], words.first[0].toUpperCase(), reason: q);
        for (final w in words.skip(1)) {
          final ok = w == w.toLowerCase() || w == w.toUpperCase() || w == 'I';
          expect(ok, isTrue, reason: '$q: $w');
        }
      }
    }
  });

  test('graduates are offered what final-years are', () {
    expect(startersFor(YearMode.graduate), startersFor(YearMode.launch));
  });
}
