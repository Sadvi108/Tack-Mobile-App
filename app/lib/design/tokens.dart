import 'package:flutter/widgets.dart';

/// Which palette the app is currently painting with.
///
/// Held statically rather than passed through context, because the 454
/// references to [TackColors] across 49 files read it without one — and
/// rewriting every call site to take a BuildContext would be a far larger and
/// riskier change than the feature is worth.
///
/// The app root rebuilds the whole tree when this changes, so nothing is left
/// painted in the old palette. See TackApp.
class TackBrightness {
  const TackBrightness._();

  static Brightness _current = Brightness.light;

  static Brightness get current => _current;
  static bool get isDark => _current == Brightness.dark;

  /// Set once at the top of the tree, before anything paints.
  static void set(Brightness brightness) => _current = brightness;
}

/// Every colour, spacing step, radius and duration in Tack.
///
/// These are the values from the design handoff. Contrast rules that were
/// audited and must be preserved:
///   - [strokeFaint] is a stroke and disabled-fill colour. Never text.
///   - Teal and amber as *text* use [tealText] / [amberText], not the fills.
///   - [muted] is the only secondary text colour. It passes AA on both
///     [white] (6.25:1) and [sailWhite] (5.43:1).
///
/// Each one resolves against [TackBrightness]. They are getters rather than
/// constants so the palette can change without touching a call site; the six
/// places that wanted them inside a `const` expression were changed instead,
/// which was cheaper than the alternative by two orders of magnitude.
class TackColors {
  const TackColors._();

  static Color _p(Color light, Color dark) =>
      TackBrightness.isDark ? dark : light;

  // ------------------------------------------------------------------ brand
  //
  // maroon is a *fill*: the colour behind white text on a button or a feature
  // card. maroonText is the same brand as ink on a surface.
  //
  // In light mode they are the same colour, because #7A1B34 works both ways on
  // white. In dark mode they cannot be: a fill needs to stay dark enough for
  // white text to pass AA on it, and text needs to be light enough to pass AA
  // on a near-black card. Those two luminance windows do not overlap, so one
  // token cannot do both jobs — the same reason teal and amber have carried
  // separate text variants since the handoff.
  static Color get maroon =>
      _p(const Color(0xFF7A1B34), const Color(0xFF8E2440));
  static Color get maroonText =>
      _p(const Color(0xFF7A1B34), const Color(0xFFEE8FA3));
  static Color get maroonDeep =>
      _p(const Color(0xFF5E1428), const Color(0xFF6B1A2F));
  static Color get maroonTint =>
      _p(const Color(0xFFF3E7EA), const Color(0xFF3A2129));
  static Color get maroonPale =>
      _p(const Color(0xFFFBF4F5), const Color(0xFF2A1B20));

  // ------------------------------------------------------------------- teal
  static Color get teal => _p(const Color(0xFF5DCAA5), const Color(0xFF3F9C7E));
  static Color get tealText =>
      _p(const Color(0xFF1A6B50), const Color(0xFF7FD8B6));
  static Color get tealTint =>
      _p(const Color(0xFFEAF8F2), const Color(0xFF15332A));
  static Color get tealDeepTint =>
      _p(const Color(0xFFE4F0EB), const Color(0xFF1B3A31));

  // ------------------------------------------------------------------ amber
  static Color get amber =>
      _p(const Color(0xFFFAC775), const Color(0xFFC9964A));
  static Color get amberText =>
      _p(const Color(0xFF8A6415), const Color(0xFFF0C87E));
  static Color get amberTint =>
      _p(const Color(0xFFFDF6E7), const Color(0xFF372C15));

  // --------------------------------------------------------------- surfaces
  //
  // Warm rather than neutral greys: the light palette is warm and a cold
  // charcoal underneath the same maroon reads as a different product.
  //
  // `white` keeps its name because it is the card surface, not the colour
  // white. Renaming it would have touched 33 call sites to say the same thing.
  static Color get white =>
      _p(const Color(0xFFFFFFFF), const Color(0xFF1E1A19));
  static Color get sailWhite =>
      _p(const Color(0xFFF1EFE8), const Color(0xFF141110));

  // ------------------------------------------------------------------- text
  static Color get ink => _p(const Color(0xFF23181C), const Color(0xFFF2EDEA));
  static Color get muted =>
      _p(const Color(0xFF6E5B61), const Color(0xFFA9999E));

  // ---------------------------------------------------------------- strokes
  static Color get line => _p(const Color(0xFFEDE7E4), const Color(0xFF2E2825));
  static Color get line2 =>
      _p(const Color(0xFFDCD4CF), const Color(0xFF3E3632));
  static Color get strokeFaint =>
      _p(const Color(0xFFC9B6BC), const Color(0xFF5A4A4F));

  // ------------------------------------------------------------------ other
  static Color get blueTint =>
      _p(const Color(0xFFEAF0F8), const Color(0xFF1B2735));
  static Color get blueText =>
      _p(const Color(0xFF2E5C8A), const Color(0xFF8FB6E0));
  // danger splits the same way maroon does, and for the same reason: it is the
  // fill behind white text on a destructive button *and* the colour of a field
  // error under an input. One value cannot be both once the page goes dark.
  static Color get danger =>
      _p(const Color(0xFFA32B2B), const Color(0xFFBE4040));
  static Color get dangerText =>
      _p(const Color(0xFFA32B2B), const Color(0xFFEF8B8B));

  /// The "nothing scored yet" bar colour on the readiness breakdown.
  static Color get zeroHealth =>
      _p(const Color(0xFFE4A0A0), const Color(0xFF7A4444));

  static Color get scrim =>
      _p(const Color(0x7323181C), const Color(0xA6000000));

  /// Always white, in both palettes: the text and icons that sit on a filled
  /// brand button or a maroon card, where the fill is dark in either mode.
  static const onBrand = Color(0xFFFFFFFF);

  /// Always near-black, in both palettes: what sits on the *light* fills.
  ///
  /// [amber] and [teal] are mid-tones in light and dark alike — neither ever
  /// gets dark enough for white text to clear AA on it — so their foreground
  /// is the one that must not flip toward the light. The inverse of [onBrand],
  /// and the reason the completed roadmap node carries a dark tick rather than
  /// a white one.
  static const onAccent = Color(0xFF23181C);

  /// The one warning colour that reads on a maroon fill in both palettes.
  ///
  /// [amber] is too dark against dark-mode maroon (3.2:1) and [amberText] too
  /// dark against light-mode maroon (1.9:1); neither survives both. The light
  /// amber does, at 6.6:1 and 5.4:1 — so "2 days late" on the week card is
  /// fixed rather than themed.
  static const warnOnBrand = Color(0xFFFAC775);
}

class TackSpace {
  const TackSpace._();

  /// Horizontal padding for every screen body.
  static const screen = 20.0;

  /// Onboarding and the landing page breathe slightly wider.
  static const screenWide = 22.0;

  static const cardX = 20.0;
  static const cardY = 18.0;
  static const cardCompactX = 18.0;
  static const cardCompactY = 16.0;

  /// Gap between stacked cards.
  static const stack = 12.0;
  static const stackLoose = 14.0;

  /// Gap between rows inside a list.
  static const row = 10.0;
  static const rowLoose = 11.0;

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// The minimum height of anything tappable.
  static const tapTarget = 44.0;
}

class TackRadius {
  const TackRadius._();

  static const card = Radius.circular(20);
  static const listCard = Radius.circular(18);
  static const input = Radius.circular(12);
  static const button = Radius.circular(14);
  static const buttonRound = Radius.circular(27);
  static const pill = Radius.circular(22);
  static const sheet = Radius.circular(24);

  static const cardAll = BorderRadius.all(card);
  static const listCardAll = BorderRadius.all(listCard);
  static const inputAll = BorderRadius.all(input);
  static const buttonAll = BorderRadius.all(button);
  static const pillAll = BorderRadius.all(pill);
  static const sheetTop = BorderRadius.vertical(top: sheet);
}

/// Elevation is deliberately minimal. Emphasis is done with a 1.5px maroon
/// border, not with shadow — see "Your next three actions" on the dashboard.
class TackShadow {
  const TackShadow._();

  static const resting = <BoxShadow>[
    BoxShadow(color: Color(0x0F23181C), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Only for the one card that overlaps a header.
  static const raised = <BoxShadow>[
    BoxShadow(color: Color(0x1A23181C), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static const fab = <BoxShadow>[
    BoxShadow(color: Color(0x597A1B34), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Short and cheap. Anything that costs a repaint on a mid-range Android is
/// out of budget.
class TackMotion {
  const TackMotion._();

  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 200);
  static const curve = Curves.easeOut;

  /// One-shot reveals only: the score ring sweeping to its value, a figure
  /// counting up, a card arriving as the screen opens.
  ///
  /// Longer than [normal] on purpose, and the exception is narrow. The 150–200ms
  /// rule exists so nothing costs a repaint per frame while a student reads the
  /// screen; a reveal plays once when the data lands and then stops, so at rest
  /// it costs exactly nothing. Anything that repeats, loops or reacts to scroll
  /// stays inside [normal] — no exceptions, because those are the ones that
  /// flatten a mid-range battery.
  static const reveal = Duration(milliseconds: 620);
  static const revealCurve = Curves.easeOutCubic;

  /// The gap between one revealed card and the next. Small enough that the
  /// whole screen has settled inside a second.
  static const stagger = Duration(milliseconds: 55);
}

/// The narrowest screen the app must work on. Layout is checked against this,
/// not against a desk-sized emulator.
const kMinScreenWidth = 360.0;
