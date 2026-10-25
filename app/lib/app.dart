import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/offline/sync.dart';
import 'design/tack.dart';
import 'features/settings/data/appearance.dart';
import 'routing/router.dart';

class TackApp extends ConsumerWidget {
  const TackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the outbox draining whenever the connection comes back.
    ref.watch(syncOnReconnectProvider);

    // Until the stored choice has been read, follow the phone. It resolves in
    // a frame or two and matching the system is the least surprising thing to
    // show in the meantime.
    final appearance = ref.watch(appearanceProvider).value ?? Appearance.system;

    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (appearance) {
      Appearance.light => Brightness.light,
      Appearance.dark => Brightness.dark,
      Appearance.system => platform,
    };

    // Every TackColors member reads this, so it has to be right before the
    // themes below are built.
    TackBrightness.set(brightness);

    return PaletteScope(
      brightness: brightness,
      child: MaterialApp.router(
        // Keyed on the palette so changing it discards the tree and rebuilds it.
        //
        // Without this, `const` widgets keep their old colours: Flutter
        // canonicalises a const instance and skips rebuilding it when the parent
        // produces an identical one, so half the app would stay light. The
        // screens already open survive the key, inside the router's navigator;
        // PaletteScope above rebuilds those.
        key: ValueKey(brightness),
        title: 'Tack',
        debugShowCheckedModeBanner: false,
        theme: buildTackTheme(Brightness.light),
        darkTheme: buildTackTheme(Brightness.dark),
        themeMode: appearance.mode,
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) {
          // buildTackTheme sets the palette as a side effect, and Flutter builds
          // whichever of theme/darkTheme it needs — so the holder can be left on
          // the wrong one by the time the tree paints. Setting it here, inside
          // the build, is what guarantees the widgets below agree with the
          // ThemeData above them.
          TackBrightness.set(brightness);

          // The design is fixed at a 360px baseline and audited at 16px body
          // text. Honour the user's larger text sizes, but cap the scale so the
          // pinned CTA cannot be pushed off a short screen.
          final scale = MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scale),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Rebuilds everything below it, once, when the palette changes.
///
/// Keying MaterialApp on the palette is not enough on its own. The router's
/// navigator holds a global key, so it is moved into the new tree with every
/// open screen still built, and a widget there that reads [TackColors]
/// without depending on the Theme keeps the palette it was built in: a const
/// widget never rebuilds, and most of the rest do not either. Marking every
/// element dirty is what hot reload does, and it costs one frame, only when
/// somebody changes the setting.
class PaletteScope extends StatefulWidget {
  const PaletteScope({
    super.key,
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  @override
  void didUpdateWidget(PaletteScope old) {
    super.didUpdateWidget(old);
    if (old.brightness == widget.brightness) return;
    // After this frame: nothing may be marked dirty while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
