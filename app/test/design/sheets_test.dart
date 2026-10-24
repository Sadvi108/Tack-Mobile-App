import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';

import '../helpers.dart';

/// Pumps an empty page at the short Android size and hands back a context
/// that sheets can be opened from.
Future<BuildContext> _page(WidgetTester tester, {Widget? body}) async {
  tester.view.physicalSize = shortAndroid;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late BuildContext page;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTackTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            page = context;
            return body ?? const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return page;
}

void main() {
  group('add your own', () {
    Widget grid(ValueChanged<String> onAddOwn) => TackChipGrid(
      options: const [PickerOption(value: 'a', label: 'Sports')],
      selected: const {},
      onToggle: (_) {},
      onAddOwn: onAddOwn,
    );

    // Tapping outside closed the sheet while its text box was still on screen
    // for the closing animation, and the controller under it had already been
    // thrown away. The app went to a red screen in the middle of onboarding.
    testWidgets('closing it by tapping outside does not crash', (tester) async {
      await _page(tester, body: grid((_) {}));

      await tester.tap(find.text('+ Add your own'));
      await tester.pumpAndSettle();
      expect(find.text('Add it'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add it'), findsNothing);
    });

    testWidgets('what is typed is what gets added', (tester) async {
      String? added;
      await _page(tester, body: grid((value) => added = value));

      await tester.tap(find.text('+ Add your own'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Debate club ');
      await tester.tap(find.text('Add it'));
      await tester.pumpAndSettle();

      expect(added, 'Debate club');
      expect(tester.takeException(), isNull);
    });
  });

  // The picker put "Not sure yet" first with a sort that is not stable, and
  // on a long list that shuffled everything else: the country list opened on
  // Ethiopia, with Bangladesh — first in the database — nowhere near the top.
  testWidgets('a search picker keeps the order it was given', (tester) async {
    final page = await _page(tester);
    final given = [
      for (var i = 0; i < 60; i++)
        PickerOption(value: '$i', label: 'Place ${'$i'.padLeft(2, '0')}'),
    ];

    showSearchPicker<String>(
      context: page,
      title: 'Country',
      load: () async => [
        const PickerOption(
          value: 'unsure',
          label: 'Not sure yet',
          highlighted: true,
        ),
        ...given,
      ],
    );
    await tester.pumpAndSettle();

    final shown = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^(Place|Not sure)')))
        .map((t) => t.data)
        .toList();
    expect(shown.first, 'Not sure yet');
    expect(shown.skip(1).take(5), [
      'Place 00',
      'Place 01',
      'Place 02',
      'Place 03',
      'Place 04',
    ]);
  });

  group('sheets and the keyboard', () {
    // Every picker search and "Add your own" box sat under the keyboard: the
    // sheet stayed pinned to the bottom of the screen while the keyboard
    // covered it, so a student typed into something they could not see.
    testWidgets('a sheet with a text box sits above the keyboard', (
      tester,
    ) async {
      final page = await _page(tester);
      addTearDown(tester.view.resetViewInsets);

      showTackSheet<void>(
        context: page,
        title: 'Search',
        child: const Padding(
          padding: EdgeInsets.all(TackSpace.screen),
          child: TextField(key: Key('box')),
        ),
      );
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.byKey(const Key('box'))).dy,
        lessThanOrEqualTo(shortAndroid.height - 300),
      );
      expect(tester.takeException(), isNull);
    });

    // The sheet makes room for the keyboard once. Contents that also add the
    // keyboard height would leave a blank band the height of the keyboard.
    testWidgets('what is inside a sheet is not told about the keyboard', (
      tester,
    ) async {
      final page = await _page(tester);
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);

      showTackSheet<void>(
        context: page,
        title: 'Search',
        child: Builder(
          builder: (inside) =>
              Text('inset ${MediaQuery.viewInsetsOf(inside).bottom}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('inset 0.0'), findsOneWidget);
    });

    // Picking a country with the name field focused handed focus back to the
    // name field when the sheet closed, and the keyboard came up over the
    // rest of the form every time.
    testWidgets('closing a sheet does not reopen the keyboard on the page', (
      tester,
    ) async {
      final name = FocusNode();
      addTearDown(name.dispose);
      final page = await _page(tester, body: TextField(focusNode: name));

      name.requestFocus();
      await tester.pump();
      expect(name.hasFocus, isTrue);

      final picked = showTackSheet<String>(
        context: page,
        title: 'Country',
        child: Builder(
          builder: (inside) => TextButton(
            onPressed: () => Navigator.of(inside).pop('BD'),
            child: const Text('Bangladesh'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bangladesh'));
      await tester.pumpAndSettle();

      expect(await picked, 'BD');
      expect(name.hasFocus, isFalse);
    });
  });
}
