import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/ai/allowance.dart';
import 'package:tack/core/supabase/client.dart';

void main() {
  // The daily limit is defined once, on the server. A screen may say what is
  // left; it never says what the whole allowance is (R14), so the line is
  // built from the remaining count alone.
  group('the allowance line', () {
    test('none left', () {
      expect(
        allowanceLine(const AiAllowance(used: 4, limit: 4)),
        'No AI actions left today',
      );
    });

    test('one left', () {
      expect(
        allowanceLine(const AiAllowance(used: 3, limit: 4)),
        'One AI action left today',
      );
    });

    test('several left', () {
      expect(
        allowanceLine(const AiAllowance(used: 1, limit: 8)),
        '7 AI actions left today',
      );
    });

    test('never names the limit', () {
      // Some used, so what is left never equals the limit by chance.
      for (final used in [1, 5, 11, 12]) {
        final line = allowanceLine(AiAllowance(used: used, limit: 12));
        expect(line, isNot(contains('12')));
        expect(line, isNot(contains(' of ')));
      }
    });
  });

  group('reading the allowance', () {
    test('more used than allowed is none left, never a negative', () {
      const allowance = AiAllowance(used: 9, limit: 4);
      expect(allowance.remaining, 0);
      expect(allowance.isSpent, isTrue);
    });

    test('a malformed row reads as nothing left rather than failing', () {
      final allowance = AiAllowance.fromRow({'used': 'two', 'limit': -3});
      expect(allowance.limit, 0);
      expect(allowance.remaining, 0);
      expect(AiAllowance.fromRow(null).isSpent, isTrue);
    });

    test('a row from the server is read as numbers', () {
      final allowance = AiAllowance.fromRow({'used': 2, 'limit': 5.0});
      expect(allowance.used, 2);
      expect(allowance.limit, 5);
      expect(allowance.remaining, 3);
    });

    test('signed out, nothing is asked of the server', () async {
      final container = ProviderContainer(
        overrides: [currentUserProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      final allowance = await container.read(aiAllowanceProvider.future);
      expect(allowance.used, 0);
      expect(allowance.limit, 0);
    });
  });
}
