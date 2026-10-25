import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/app.dart';
import 'package:tack/design/tack.dart';

/// Changing the palette has to repaint the screen that is open.
///
/// TackApp keys MaterialApp on the palette so the tree is thrown away, but the
/// router's navigator keeps a global key: it is moved into the new tree with
/// every open screen still built. A const widget on that screen, or anything
/// else that reads TackColors without a Theme dependency, kept the palette it
/// was built in. Switching to light in Settings left the page dark behind
/// light cards, the title dark on dark, and the dividers black.
void main() {
  tearDown(() => TackBrightness.set(Brightness.light));

  Future<void> pump(WidgetTester tester, ValueNotifier<Brightness> palette) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: _Swatch()),
        ),
      ],
    );
    addTearDown(router.dispose);
    return tester.pumpWidget(
      ValueListenableBuilder<Brightness>(
        valueListenable: palette,
        builder: (context, brightness, _) {
          TackBrightness.set(brightness);
          return PaletteScope(
            brightness: brightness,
            child: MaterialApp.router(
              key: ValueKey(brightness),
              routerConfig: router,
            ),
          );
        },
      ),
    );
  }

  Color swatch(WidgetTester tester) =>
      tester.widget<ColoredBox>(find.byKey(_Swatch.box)).color;

  testWidgets('a const widget on an open screen takes the new palette', (
    tester,
  ) async {
    final palette = ValueNotifier(Brightness.light);
    addTearDown(palette.dispose);
    await pump(tester, palette);
    final light = swatch(tester);

    palette.value = Brightness.dark;
    await tester.pumpAndSettle();

    TackBrightness.set(Brightness.dark);
    expect(swatch(tester), TackColors.sailWhite);
    expect(swatch(tester), isNot(light));
  });

  testWidgets('and back again', (tester) async {
    final palette = ValueNotifier(Brightness.dark);
    addTearDown(palette.dispose);
    await pump(tester, palette);

    palette.value = Brightness.light;
    await tester.pumpAndSettle();

    TackBrightness.set(Brightness.light);
    expect(swatch(tester), TackColors.sailWhite);
  });
}

class _Swatch extends StatelessWidget {
  const _Swatch();

  static const box = Key('swatch');

  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: box, color: TackColors.sailWhite);
}
