// Every foreground/background pair the design actually puts together, checked
// against WCAG AA in both palettes.
//
// This exists because dark mode broke contrast in a way no widget test could
// see. `TackColors.white` was the card surface *and* the text on a maroon
// button; when the surface flipped to near-black, so did the button label.
// Screenshots caught the loud ones. The quiet ones — near-white `ink` on
// `amber` at 2.3:1 — needed arithmetic.
//
// A pair listed here is a promise the palette makes. Adding a colour is free;
// pairing it with something is what has to be earned.
import 'dart:math' as math;

import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// AA is 4.5:1 for body text, 3:1 for large text (>=18.66px bold or 24px) and
/// for the boundary of a control. Each pair says which one it is claiming.
const _body = 4.5;
const _large = 3.0;

typedef Pair = (
  String what,
  Color Function() fg,
  Color Function() bg,
  double min,
);

final _pairs = <Pair>[
  // --- body text on the two surfaces
  ('ink on a card', () => TackColors.ink, () => TackColors.white, _body),
  ('ink on the page', () => TackColors.ink, () => TackColors.sailWhite, _body),
  ('muted on a card', () => TackColors.muted, () => TackColors.white, _body),
  (
    'muted on the page',
    () => TackColors.muted,
    () => TackColors.sailWhite,
    _body,
  ),

  // --- text and icons on a brand fill
  (
    'onBrand on maroon',
    () => TackColors.onBrand,
    () => TackColors.maroon,
    _body,
  ),
  (
    'onBrand on pressed maroon',
    () => TackColors.onBrand,
    () => TackColors.maroonDeep,
    _body,
  ),
  (
    'onBrand on danger',
    () => TackColors.onBrand,
    () => TackColors.danger,
    _body,
  ),
  (
    'onAccent on teal',
    () => TackColors.onAccent,
    () => TackColors.teal,
    _large,
  ),
  (
    'onAccent on amber',
    () => TackColors.onAccent,
    () => TackColors.amber,
    _body,
  ),

  // --- brand as text
  (
    'maroonText on a card',
    () => TackColors.maroonText,
    () => TackColors.white,
    _body,
  ),
  (
    'maroonText on the page',
    () => TackColors.maroonText,
    () => TackColors.sailWhite,
    _body,
  ),
  (
    'maroonText on its tint',
    () => TackColors.maroonText,
    () => TackColors.maroonTint,
    _body,
  ),
  (
    'maroonText on its pale tint',
    () => TackColors.maroonText,
    () => TackColors.maroonPale,
    _body,
  ),
  (
    'tealText on a card',
    () => TackColors.tealText,
    () => TackColors.white,
    _body,
  ),
  (
    'tealText on the page',
    () => TackColors.tealText,
    () => TackColors.sailWhite,
    _body,
  ),
  (
    'tealText on its tint',
    () => TackColors.tealText,
    () => TackColors.tealTint,
    _body,
  ),
  (
    'tealText on its deep tint',
    () => TackColors.tealText,
    () => TackColors.tealDeepTint,
    _body,
  ),
  (
    'amberText on a card',
    () => TackColors.amberText,
    () => TackColors.white,
    _body,
  ),
  (
    'amberText on the page',
    () => TackColors.amberText,
    () => TackColors.sailWhite,
    _body,
  ),
  (
    'amberText on its tint',
    () => TackColors.amberText,
    () => TackColors.amberTint,
    _body,
  ),
  (
    'blueText on its tint',
    () => TackColors.blueText,
    () => TackColors.blueTint,
    _body,
  ),
  (
    'dangerText on a card',
    () => TackColors.dangerText,
    () => TackColors.white,
    _body,
  ),
  (
    'dangerText on the page',
    () => TackColors.dangerText,
    () => TackColors.sailWhite,
    _body,
  ),

  // --- text on a maroon feature card, which is a fill in both palettes
  (
    'onBrand on a maroon card',
    () => TackColors.onBrand,
    () => TackColors.maroon,
    _body,
  ),
  (
    'warnOnBrand on a maroon card',
    () => TackColors.warnOnBrand,
    () => TackColors.maroon,
    _body,
  ),

  // --- boundaries: a control's edge has to be findable, not readable
  ('line2 against a card', () => TackColors.line2, () => TackColors.white, 1.3),
  (
    'strokeFaint against a card',
    () => TackColors.strokeFaint,
    () => TackColors.white,
    1.6,
  ),
  // An error or focus ring is how a field says something is wrong, so it is
  // held to the 3:1 WCAG asks of a control boundary rather than to the
  // decorative floor the other two strokes get.
  (
    'the error ring against a card',
    () => TackColors.danger,
    () => TackColors.white,
    _large,
  ),
  (
    'the focus ring against a card',
    () => TackColors.maroonText,
    () => TackColors.white,
    _large,
  ),
];

void main() {
  tearDown(() => TackBrightness.set(Brightness.light));

  for (final brightness in Brightness.values) {
    group('${brightness.name} palette', () {
      for (final (what, fg, bg, min) in _pairs) {
        test('$what clears $min:1', () {
          TackBrightness.set(brightness);
          final ratio = contrast(fg(), bg());
          expect(
            ratio,
            greaterThanOrEqualTo(min),
            reason:
                '$what is ${ratio.toStringAsFixed(2)}:1 in ${brightness.name}, '
                'below the $min:1 this pair claims.',
          );
        });
      }
    });
  }
}
