import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/profile/data/profile.dart';

/// The profile card showed ten loose digits while Settings showed the same
/// number with +880 in front. Both read this now.
void main() {
  Profile withPhone(String? phone) => Profile(id: 'u1', phone: phone);

  test('a number saved without a prefix gets the country code', () {
    expect(withPhone('1789666154').displayPhone, '+880 1789666154');
  });

  test('a local number loses its trunk zero behind the code', () {
    expect(withPhone('01789666154').displayPhone, '+880 1789666154');
  });

  test('a number already saved with its prefix is not prefixed twice', () {
    expect(withPhone('+8801712345678').displayPhone, '+8801712345678');
  });

  test('no number means nothing to show', () {
    expect(withPhone(null).displayPhone, isNull);
    expect(withPhone('  ').displayPhone, isNull);
  });
}
