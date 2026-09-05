import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';
import 'cards.dart';

/// Empty states matter more than full ones — most students arrive with
/// nothing. Every one of these names what to do next rather than only
/// reporting that there is nothing here.
class TackEmptyState extends StatelessWidget {
  const TackEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.graphic,
  });

  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? graphic;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          graphic ?? const TackZigzagGraphic(),
          const SizedBox(height: TackSpace.lg),
          Text(
            title,
            style: TackText.sectionHeader,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TackSpace.sm),
          Text(body, style: TackText.bodyMuted, textAlign: TextAlign.center),
          if (primaryLabel != null) ...[
            const SizedBox(height: TackSpace.xl),
            TackButton(primaryLabel!, onPressed: onPrimary),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: TackSpace.row),
            TackButton.secondary(secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

/// The zigzag motif again, in neutral grey with an amber destination dot.
class TackZigzagGraphic extends StatelessWidget {
  const TackZigzagGraphic({super.key, this.width = 130});

  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 66 / 120),
    painter: _ZigzagPainter(),
  );
}

class _ZigzagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 120;
    canvas.drawPath(
      Path()
        ..moveTo(8 * s, 58 * s)
        ..lineTo(34 * s, 36 * s)
        ..lineTo(56 * s, 46 * s)
        ..lineTo(82 * s, 22 * s)
        ..lineTo(104 * s, 32 * s),
      Paint()
        ..color = TackColors.line2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(112 * s, 16 * s),
      6 * s,
      Paint()..color = TackColors.amber,
    );
  }

  @override
  bool shouldRepaint(_ZigzagPainter old) => false;
}

/// Shown when the device is offline. Tack is read-write offline for tasks and
/// applications, and the copy says so rather than implying nothing works.
class TackOfflineState extends StatelessWidget {
  const TackOfflineState({super.key, this.queuedChanges = 0, this.onRetry});

  final int queuedChanges;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: TackColors.amberTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackIcon(TackIcons.offline, size: 22, color: TackColors.amberText),
          const SizedBox(width: TackSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You are offline', style: TackText.cardTitle),
                const SizedBox(height: TackSpace.xs),
                Text(
                  queuedChanges > 0
                      ? 'Keep working. $queuedChanges ${queuedChanges == 1 ? 'change is' : 'changes are'} saved on '
                            'this phone and will sync when you are back online.'
                      : 'Keep working. Tasks and applications save on this phone and sync when you are '
                            'back online.',
                  style: TackText.bodyMuted,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: TackSpace.md),
                  TackButton.ghost(
                    'Try again',
                    onPressed: onRetry,
                    fullWidth: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Something failed. Never blames the user; says what happened and what to do.
class TackErrorState extends StatelessWidget {
  const TackErrorState({
    super.key,
    this.title = 'That did not load',
    required this.body,
    this.onRetry,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TackIcon(TackIcons.alert, size: 22, color: TackColors.dangerText),
              const SizedBox(width: TackSpace.sm),
              Expanded(child: Text(title, style: TackText.cardTitle)),
            ],
          ),
          const SizedBox(height: TackSpace.sm),
          Text(body, style: TackText.bodyMuted),
          if (onRetry != null) ...[
            const SizedBox(height: TackSpace.lg),
            TackButton.secondary('Try again', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// The daily AI limit, explained as a tradeoff that keeps the app free rather
/// than as a punishment, and pointing at work the student can still do.
class TackQuotaState extends StatelessWidget {
  const TackQuotaState({
    super.key,
    required this.resetsAt,
    required this.limit,
    this.onGoToRoadmap,
  });

  final String resetsAt;

  /// Read from the server. Hardcoding it here is how the app came to tell
  /// students a number the database had stopped agreeing with.
  final int limit;
  final VoidCallback? onGoToRoadmap;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      background: TackColors.amberTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You have used today\'s AI actions', style: TackText.cardTitle),
          const SizedBox(height: TackSpace.sm),
          Text(
            'Every student gets $limit a day, which is how Tack stays free for '
            'everyone. Plenty here costs nothing at all — checking your CV, '
            'practising interviews, Radar. Your next $limit arrive at $resetsAt.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.lg),
          TackButton('Work on your roadmap instead', onPressed: onGoToRoadmap),
        ],
      ),
    );
  }
}

/// The striped placeholder used where an image would otherwise go. There is no
/// photography anywhere in Tack, deliberately.
class TackPlaceholderFill extends StatelessWidget {
  const TackPlaceholderFill({super.key, this.height = 84, this.child});

  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: TackRadius.inputAll,
        border: Border.all(color: TackColors.line2, width: 1.5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          tileMode: TileMode.repeated,
          stops: [0, 0.5, 0.5, 1],
          colors: [
            Color(0xFFFBFAF7),
            Color(0xFFFBFAF7),
            Color(0xFFF5F2EC),
            Color(0xFFF5F2EC),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
