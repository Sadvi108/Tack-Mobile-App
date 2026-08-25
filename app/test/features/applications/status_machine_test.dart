import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/data/status_machine.dart';

void main() {
  group('the Dart table agrees with the database', () {
    // Exported from the live database with:
    //   select f.from_s, t.to_s, public.is_valid_status_transition(f.from_s, t.to_s)
    //   from unnest(enum_range(null::application_status)) f(from_s),
    //        unnest(enum_range(null::application_status)) t(to_s);
    //
    // If these ever disagree the UI offers a move the server will refuse, so
    // the whole 6x6 grid is checked rather than a handful of cases.
    test('every one of the 36 pairs matches', () {
      final rows =
          (jsonDecode(
                    File(
                      'test/features/applications/sql_transitions.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();

      expect(rows, hasLength(36), reason: 'six statuses squared');

      final disagreements = <String>[];
      for (final row in rows) {
        final from = TackStatusStyle.fromWire(row['from_status'] as String);
        final to = TackStatusStyle.fromWire(row['to_status'] as String);
        final sqlSays = row['allowed'] as bool;
        final dartSays = StatusMachine.canMove(from, to);
        if (sqlSays != dartSays) {
          disagreements.add(
            '${from.name} -> ${to.name}: sql=$sqlSays dart=$dartSays',
          );
        }
      }

      expect(
        disagreements,
        isEmpty,
        reason: 'the client must never offer a move the database will refuse',
      );
    });
  });

  group('the moves the tracker offers', () {
    test('a saved job can only be marked applied, or rejected', () {
      expect(
        StatusMachine.movesFrom(TackStatus.saved),
        containsAll([TackStatus.applied, TackStatus.rejected]),
      );
      expect(StatusMachine.movesFrom(TackStatus.saved), hasLength(2));
    });

    test('an interview cannot jump straight back to saved', () {
      expect(
        StatusMachine.canMove(TackStatus.interview, TackStatus.saved),
        isFalse,
      );
    });

    test('anything can be rejected, including an offer', () {
      for (final from in TackStatus.values) {
        expect(StatusMachine.canMove(from, TackStatus.rejected), isTrue);
      }
    });

    test('a rejection can be undone, because people mistype', () {
      expect(StatusMachine.movesFrom(TackStatus.rejected), hasLength(5));
    });

    test('the one-tap move is the likely next step', () {
      expect(StatusMachine.primaryMove(TackStatus.saved), TackStatus.applied);
      expect(StatusMachine.primaryMove(TackStatus.interview), TackStatus.offer);
      expect(
        StatusMachine.primaryMove(TackStatus.offer),
        isNull,
        reason: 'there is nothing better than an offer to move to',
      );
    });

    test('every offered move is legal', () {
      for (final from in TackStatus.values) {
        for (final to in StatusMachine.movesFrom(from)) {
          expect(StatusMachine.canMove(from, to), isTrue);
        }
        final primary = StatusMachine.primaryMove(from);
        if (primary != null) {
          expect(StatusMachine.canMove(from, primary), isTrue);
        }
      }
    });
  });
}
