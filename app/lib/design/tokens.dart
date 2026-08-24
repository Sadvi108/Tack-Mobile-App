import 'package:flutter/widgets.dart';

/// Every colour, spacing step, radius and duration in Tack.
///
/// These are the values from the design handoff, unchanged. Contrast rules
/// that were audited and must be preserved:
///   - [strokeFaint] is a stroke and disabled-fill colour. Never text.
///   - Teal and amber as *text* use [tealText] / [amberText], not the fills.
///   - [muted] is the only secondary text colour. It passes AA on both
///     [white] (6.25:1) and [sailWhite] (5.43:1).
class TackColors {
  const TackColors._();

  static const maroon = Color(0xFF7A1B34);
  static const maroonDeep = Color(0xFF5E1428);
  static const maroonTint = Color(0xFFF3E7EA);
  static const maroonPale = Color(0xFFFBF4F5);

  static const teal = Color(0xFF5DCAA5);
  static const tealText = Color(0xFF1A6B50);
  static const tealTint = Color(0xFFEAF8F2);
  static const tealDeepTint = Color(0xFFE4F0EB);

  static const amber = Color(0xFFFAC775);
  static const amberText = Color(0xFF8A6415);
  static const amberTint = Color(0xFFFDF6E7);

  static const sailWhite = Color(0xFFF1EFE8);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF23181C);
  static const muted = Color(0xFF6E5B61);

  static const line = Color(0xFFEDE7E4);
  static const line2 = Color(0xFFDCD4CF);
  static const strokeFaint = Color(0xFFC9B6BC);

  static const blueTint = Color(0xFFEAF0F8);
  static const blueText = Color(0xFF2E5C8A);

  static const danger = Color(0xFFA32B2B);

  /// The "nothing scored yet" bar colour on the readiness breakdown.
  static const zeroHealth = Color(0xFFE4A0A0);

  static const scrim = Color(0x7323181C);
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
}

/// The narrowest screen the app must work on. Layout is checked against this,
/// not against a desk-sized emulator.
const kMinScreenWidth = 360.0;
