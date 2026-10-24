import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/vault/data/first_read_models.dart';
import 'package:tack/features/vault/presentation/first_read_card.dart';

import '../../helpers.dart';

final _json = {
  'chunks': [
    {'index': 1, 'section': 'Top', 'words': 12},
    {'index': 2, 'section': 'Skills', 'words': 8},
    {'index': 3, 'section': 'Experience', 'words': 40},
    {'index': 4, 'section': 'Education', 'words': 9},
  ],
  'readers': [
    {
      'persona': 'recruiter',
      'needle': [
        {'chunk': 1, 'value': 1},
        {'chunk': 2, 'value': -1},
        {'chunk': 3, 'value': -2},
      ],
      'quit_chunk': 3,
      'sayback': 'A frontend intern who builds React screens.',
      'remembered': ['cut page load time by 40 percent'],
      'one_action': 'Put the 40 percent result in your first line.',
    },
    {
      'persona': 'hiring_manager',
      'needle': [
        {'chunk': 3, 'value': 2},
      ],
      'quit_chunk': 0,
      'sayback': 'Someone who has shipped real screens.',
      'remembered': [],
      'one_action': 'Say how many users the marketplace has.',
    },
    {'persona': 'somebody else', 'needle': [], 'quit_chunk': 0},
  ],
};

void main() {
  group('reading the result', () {
    test('keeps the cast readers and says where each stopped', () {
      final read = FirstRead.fromJson(_json)!;
      expect(read.readers.map((r) => r.persona), [
        'recruiter',
        'hiring_manager',
      ]);
      expect(read.readers.first.name, 'A recruiter with eight seconds');
      expect(read.stoppedAt(read.readers.first), 'Experience');
      expect(read.stoppedAt(read.readers.last), isNull);
      expect(read.readers.first.interest(2), -1);
      expect(read.readers.last.interest(1), 0);
    });

    test('a result with no usable reader is no result', () {
      expect(FirstRead.fromJson({'chunks': [], 'readers': []}), isNull);
      expect(FirstRead.fromJson(null), isNull);
    });
  });

  group('the card', () {
    setUpAll(loadTackFonts);

    testWidgets('before a read, offers one and says what it costs', (
      tester,
    ) async {
      var asked = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: FirstReadCard(read: null, onRequest: () => asked++),
          ),
        ),
      );

      expect(find.textContaining('one AI action'), findsOneWidget);
      await tester.tap(find.text('Get a first read'));
      expect(asked, 1);
    });

    testWidgets('shows each reader, where they stopped and what stuck', (
      tester,
    ) async {
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: FirstReadCard(
              read: FirstRead.fromJson(_json),
              onRequest: () {},
            ),
          ),
        ),
      );

      expect(find.text('A recruiter with eight seconds'), findsOneWidget);
      expect(find.text('Stopped at Experience'), findsOneWidget);
      expect(find.text('Read to the end'), findsOneWidget);
      expect(
        find.textContaining('cut page load time by 40 percent'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Put the 40 percent result in your first line.'),
        findsOneWidget,
      );
      expect(find.text('Get a first read'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('while it is being read, says so and cannot be re-sent', (
      tester,
    ) async {
      var asked = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: FirstReadCard(
              read: null,
              busy: true,
              onRequest: () => asked++,
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('Reading your CV'));
      expect(asked, 0);
    });
  });
}
