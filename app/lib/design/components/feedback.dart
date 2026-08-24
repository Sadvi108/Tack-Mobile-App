import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';

enum TackToastKind { success, error, info }

/// Ink background, coloured glyph, optional action on the right. Shown above
/// the bottom nav so it never covers the tab a student is about to tap.
class TackToast {
  const TackToast._();

  static void show(
    BuildContext context, {
    required String message,
    TackToastKind kind = TackToastKind.success,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final (glyph, colour) = switch (kind) {
      TackToastKind.success => (TackIcons.check, TackColors.teal),
      TackToastKind.error => (TackIcons.alert, TackColors.amber),
      TackToastKind.info => (TackIcons.info, TackColors.amber),
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: TackColors.ink,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(
          TackSpace.lg, 0, TackSpace.lg, TackSpace.lg,
        ),
        shape: const RoundedRectangleBorder(borderRadius: TackRadius.buttonAll),
        padding: const EdgeInsets.symmetric(horizontal: TackSpace.lg, vertical: 14),
        content: Row(
          children: [
            TackIcon(glyph, size: 20, color: colour, strokeWidth: 2.4),
            const SizedBox(width: TackSpace.md),
            Expanded(
              child: Text(
                message,
                style: TackText.body.copyWith(color: TackColors.white, fontSize: 15),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: TackSpace.sm),
              GestureDetector(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                behavior: HitTestBehavior.opaque,
                child: Text(
                  actionLabel,
                  style: TackText.pill.copyWith(color: TackColors.amber, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bottom sheet used for filters, selects and confirmations. 24px top
/// corners, a 42×4 grab handle, and a scrim at rgba(35,24,28,.45).
Future<T?> showTackSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: TackColors.white,
    barrierColor: TackColors.scrim,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: TackRadius.sheetTop),
    builder: (context) => TackSheetBody(title: title, child: child),
  );
}

class TackSheetBody extends StatelessWidget {
  const TackSheetBody({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TackSpace.md),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: TackColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TackSpace.screen, TackSpace.lg, TackSpace.screen, TackSpace.md,
              ),
              child: Text(title, style: TackText.sectionHeader),
            ),
            Flexible(child: child),
            const SizedBox(height: TackSpace.sm),
          ],
        ),
      ),
    );
  }
}

/// A destructive confirmation. Returns true only on an explicit yes.
Future<bool> confirmTackAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showTackSheet<bool>(
    context: context,
    title: title,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        TackSpace.screen, 0, TackSpace.screen, TackSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body, style: TackText.bodyMuted),
          const SizedBox(height: TackSpace.xl),
          _SheetButton(
            label: confirmLabel,
            background: destructive ? TackColors.danger : TackColors.maroon,
            foreground: TackColors.white,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: TackSpace.row),
          _SheetButton(
            label: cancelLabel,
            background: TackColors.white,
            foreground: TackColors.ink,
            border: true,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: TackRadius.buttonAll,
          border: border ? Border.all(color: TackColors.line2, width: 1.5) : null,
        ),
        child: Text(label, style: TackText.button.copyWith(color: foreground)),
      ),
    );
  }
}
