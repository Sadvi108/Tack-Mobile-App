import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/features/coach/presentation/guide_citations.dart';

import '../../helpers.dart';

final _cited = [
  {
    'chunk_id': 'data-analyst:day:1',
    'path_slug': 'data-analyst',
    'path_title': 'Data analyst',
    'quote': 'Pull data with SQL',
  },
  {
    'chunk_id': 'data-analyst:salary:1',
    'path_slug': 'data-analyst',
    'path_title': 'Data analyst',
    'quote': '30,000 to 45,000 taka a month',
  },
  {
    'chunk_id': 'business-analyst:day:2',
    'path_slug': 'business-analyst',
    'path_title': 'Business analyst',
    'quote': 'Write down what they need',
  },
];

void main() {
  group('reading citations', () {
    test('a saved reply carries the guides it stood on', () {
      final message = ChatMessage.fromRow({
        'id': 'm1',
        'role': 'coach',
        'body': 'Mostly SQL.',
        'created_at': '2026-10-22T10:00:00Z',
        'answered_by': 'model',
        'citations': _cited,
      });
      expect(message.citations.length, 3);
      expect(message.citations.first.quote, 'Pull data with SQL');
      expect(message.guides.map((g) => g.slug), [
        'data-analyst',
        'business-analyst',
      ]);
      expect(message.isGrounded, isTrue);
    });

    test('a fresh reply carries them too', () {
      final reply = CoachReply.fromJson({
        'threadId': 't1',
        'remaining': 8,
        'reply': 'Mostly SQL.',
        'answeredBy': 'model',
        'citations': _cited,
      });
      expect(reply.citations.length, 3);
    });

    test('a reply from the guides that found nothing is marked as such', () {
      final message = ChatMessage.fromRow({
        'id': 'm3',
        'role': 'coach',
        'body': "Tack's career guides do not cover that yet.",
        'answered_by': 'data',
        'citations': [],
      });
      expect(message.guideRefusal, isTrue);
      expect(message.isGrounded, isFalse);

      final reply = CoachReply.fromJson({
        'threadId': 't',
        'reply': 'x',
        'answeredBy': 'model',
        'citations': [],
      });
      expect(reply.guideRefusal, isTrue);

      expect(
        ChatMessage.fromRow({
          'id': 'm4',
          'role': 'coach',
          'body': 'x',
        }).guideRefusal,
        isFalse,
      );
    });

    test('a reply without citations, or with broken ones, has none', () {
      expect(
        ChatMessage.fromRow({
          'id': 'm2',
          'role': 'coach',
          'body': 'x',
          'citations': null,
        }).citations,
        isEmpty,
      );
      expect(
        CoachReply.fromJson({
          'threadId': 't',
          'citations': [
            {'chunk_id': 'a', 'path_slug': 'b'},
            'nope',
          ],
        }).citations,
        isEmpty,
      );
    });
  });

  group('the guide chips', () {
    setUpAll(loadTackFonts);

    testWidgets('one chip per guide, and a tap opens that path', (
      tester,
    ) async {
      String? opened;
      final message = ChatMessage.fromRow({
        'id': 'm1',
        'role': 'coach',
        'body': 'Mostly SQL.',
        'citations': _cited,
      });
      await pumpAt(
        tester,
        Scaffold(
          body: GuideCitations(
            guides: message.guides,
            onOpen: (slug) => opened = slug,
          ),
        ),
      );

      expect(find.text("From Tack's career guides"), findsOneWidget);
      expect(find.text('Data analyst'), findsOneWidget);
      expect(find.text('Business analyst'), findsOneWidget);

      await tester.tap(find.text('Business analyst'));
      expect(opened, 'business-analyst');
      expect(tester.takeException(), isNull);

      // A screen reader hears a button, and a double-tap opens the guide.
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Open the Data analyst guide'),
        ),
        matchesSemantics(
          label: 'Open the Data analyst guide',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
