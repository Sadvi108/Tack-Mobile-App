import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/radar/data/listing.dart';
import 'package:tack/features/radar/data/radar_filter.dart';
import 'package:tack/features/radar/data/radar_repository.dart';
import 'package:tack/features/radar/presentation/listing_card.dart';

import '../../helpers.dart';

void main() {
  setUpAll(loadTackFonts);

  test('default search includes jobs that do not state their workplace', () {
    expect(const RadarQuery().workplace, RadarWorkplace.all);
    expect(RadarWorkplace.onsite.remoteValue, false);
    expect(RadarWorkplace.remote.remoteValue, true);
  });

  testWidgets('Bdjobs card names the source and preserves unknown workplace', (
    tester,
  ) async {
    final listing = Listing.fromJson({
      'id': 'fixture',
      'source': 'bdjobs',
      'title': 'Graduate accountant',
      'location': 'Dhaka',
      'url': 'https://bdjobs.com/h/details/1535802',
      'workplace_known': false,
      'remote': false,
    });
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: ListingCard(listing: listing, onOpen: () {}),
      ),
      size: const Size(360, 800),
    );
    expect(find.text('Bdjobs'), findsOneWidget);
    expect(find.text('Workplace not stated'), findsOneWidget);
    expect(find.text('Dhaka'), findsOneWidget);
    expect(find.text('Remote'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
