import '../../../design/tack.dart';

/// Which status moves are legal.
///
/// This mirrors `public.is_valid_status_transition` exactly. The database is
/// the authority — it rejects an illegal move whatever the client believes —
/// but the UI needs the same rules so it can offer only the moves that will
/// actually work, instead of showing options that fail on tap.
///
/// A cross-check test compares this table against the live SQL function.
class StatusMachine {
  const StatusMachine._();

  static const _allowed = <TackStatus, Set<TackStatus>>{
    TackStatus.saved: {TackStatus.applied},
    TackStatus.applied: {
      TackStatus.assessment,
      TackStatus.interview,
      TackStatus.offer,
      TackStatus.saved,
    },
    TackStatus.assessment: {
      TackStatus.interview,
      TackStatus.offer,
      TackStatus.applied,
    },
    TackStatus.interview: {TackStatus.offer, TackStatus.assessment},
    TackStatus.offer: {TackStatus.interview},
    TackStatus.rejected: {
      TackStatus.saved,
      TackStatus.applied,
      TackStatus.assessment,
      TackStatus.interview,
      TackStatus.offer,
    },
  };

  static bool canMove(TackStatus from, TackStatus to) {
    if (from == to) return true;
    // Any application can be rejected at any point, including after an offer.
    if (to == TackStatus.rejected) return true;
    return _allowed[from]?.contains(to) ?? false;
  }

  /// Every legal destination from here, excluding staying put.
  static List<TackStatus> movesFrom(TackStatus from) => [
        for (final status in TackStatus.values)
          if (status != from && canMove(from, status)) status,
      ];

  /// The single move the tracker offers as a one-tap button, so the common
  /// case does not need the full sheet.
  static TackStatus? primaryMove(TackStatus from) => switch (from) {
        TackStatus.saved => TackStatus.applied,
        TackStatus.applied => TackStatus.interview,
        TackStatus.assessment => TackStatus.interview,
        TackStatus.interview => TackStatus.offer,
        TackStatus.offer => null,
        TackStatus.rejected => null,
      };

  static String moveLabel(TackStatus to) => switch (to) {
        TackStatus.saved => 'Move back to saved',
        TackStatus.applied => 'Mark as applied',
        TackStatus.assessment => 'Got an assessment',
        TackStatus.interview => 'Got an interview',
        TackStatus.offer => 'Got an offer',
        TackStatus.rejected => 'Mark as rejected',
      };
}
