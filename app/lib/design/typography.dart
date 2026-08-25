import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The type scale from the design handoff.
///
/// Three families, all bundled as assets rather than fetched at runtime — a
/// student on 3G should not wait on a font request to read their score.
///   - Outfit  headings, numbers, section titles
///   - Inter   body, labels, buttons
///   - IBMPlexMono  small uppercase chrome labels and date stamps, never body
///
/// Body text never drops below 16px. That is an accessibility floor, not a
/// preference.
class TackText {
  const TackText._();

  static const _outfit = 'Outfit';
  static const _inter = 'Inter';
  static const _mono = 'IBMPlexMono';

  // ---------------------------------------------------------------- display
  static const landingH1 = TextStyle(
    fontFamily: _outfit,
    fontSize: 34,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.68,
    color: TackColors.ink,
  );

  static const screenTitle = TextStyle(
    fontFamily: _outfit,
    fontSize: 25,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: TackColors.ink,
  );

  static const sectionHeader = TextStyle(
    fontFamily: _outfit,
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.19,
    color: TackColors.ink,
  );

  static const cardTitle = TextStyle(
    fontFamily: _outfit,
    fontSize: 16.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: TackColors.ink,
  );

  /// The score ring. Size varies by context, so callers use `.copyWith`.
  static const heroNumber = TextStyle(
    fontFamily: _outfit,
    fontSize: 54,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.08,
    color: TackColors.maroon,
  );

  // ------------------------------------------------------------------- body
  static const body = TextStyle(
    fontFamily: _inter,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: TackColors.ink,
  );

  static const bodyLarge = TextStyle(
    fontFamily: _inter,
    fontSize: 17,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: TackColors.ink,
  );

  static const bodyMuted = TextStyle(
    fontFamily: _inter,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: TackColors.muted,
  );

  static const rowTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: TackColors.ink,
  );

  static const meta = TextStyle(
    fontFamily: _inter,
    fontSize: 14.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: TackColors.muted,
  );

  // --------------------------------------------------------------- controls
  static const button = TextStyle(
    fontFamily: _inter,
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: TackColors.white,
  );

  static const buttonSmall = TextStyle(
    fontFamily: _inter,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: TackColors.maroon,
  );

  static const fieldLabel = TextStyle(
    fontFamily: _inter,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: TackColors.ink,
  );

  static const fieldError = TextStyle(
    fontFamily: _inter,
    fontSize: 13.5,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: TackColors.danger,
  );

  static const chip = TextStyle(
    fontFamily: _inter,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: TackColors.ink,
  );

  static const pill = TextStyle(
    fontFamily: _inter,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  static const tabLabel = TextStyle(
    fontFamily: _inter,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: TackColors.muted,
  );

  static const tabLabelActive = TextStyle(
    fontFamily: _inter,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: TackColors.maroon,
  );

  // -------------------------------------------------------------- mono chrome
  /// Small uppercase section labels and date stamps. Chrome only.
  static const monoLabel = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: TackColors.muted,
  );

  static const monoLabelSmall = TextStyle(
    fontFamily: _mono,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.05,
    color: TackColors.muted,
  );
}
