import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

enum TackButtonVariant { primary, secondary, ghost, amber }

/// The one button in Tack.
///
/// Full width by default and 52–54px tall, because the primary action has to
/// be reachable with a thumb on a 640px-tall phone. The loading state swaps
/// the label for a spinner and keeps the width, so the layout never jumps.
class TackButton extends StatefulWidget {
  const TackButton(
    this.label, {
    super.key,
    this.onPressed,
    this.variant = TackButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.fullWidth = true,
    this.rounded = false,
  });

  const TackButton.secondary(String label, {Key? key, VoidCallback? onPressed, bool loading = false, Widget? icon, bool fullWidth = true, bool rounded = false})
      : this(label, key: key, onPressed: onPressed, variant: TackButtonVariant.secondary, loading: loading, icon: icon, fullWidth: fullWidth, rounded: rounded);

  const TackButton.ghost(String label, {Key? key, VoidCallback? onPressed, bool loading = false, Widget? icon, bool fullWidth = true})
      : this(label, key: key, onPressed: onPressed, variant: TackButtonVariant.ghost, loading: loading, icon: icon, fullWidth: fullWidth);

  const TackButton.amber(String label, {Key? key, VoidCallback? onPressed, bool loading = false, Widget? icon, bool fullWidth = true, bool rounded = true})
      : this(label, key: key, onPressed: onPressed, variant: TackButtonVariant.amber, loading: loading, icon: icon, fullWidth: fullWidth, rounded: rounded);

  final String label;
  final VoidCallback? onPressed;
  final TackButtonVariant variant;
  final bool loading;
  final Widget? icon;
  final bool fullWidth;
  final bool rounded;

  bool get _enabled => onPressed != null && !loading;

  @override
  State<TackButton> createState() => _TackButtonState();
}

class _TackButtonState extends State<TackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    final enabled = widget._enabled;

    final height = v == TackButtonVariant.ghost ? 48.0 : 54.0;
    final radius = widget.rounded
        ? BorderRadius.circular(height / 2)
        : TackRadius.buttonAll;

    late final Color background;
    late final Color foreground;
    Border? border;

    switch (v) {
      case TackButtonVariant.primary:
        background = !enabled
            ? TackColors.line2
            : _pressed
                ? TackColors.maroonDeep
                : TackColors.maroon;
        foreground = enabled ? TackColors.white : TackColors.muted;
      case TackButtonVariant.secondary:
        background = TackColors.white;
        foreground = enabled ? TackColors.maroon : TackColors.muted;
        border = Border.all(
          color: !enabled
              ? TackColors.line2
              : _pressed
                  ? TackColors.maroon
                  : TackColors.line2,
          width: 1.5,
        );
      case TackButtonVariant.ghost:
        background = _pressed && enabled ? TackColors.maroonTint : Colors.transparent;
        foreground = enabled ? TackColors.maroon : TackColors.muted;
      case TackButtonVariant.amber:
        background = !enabled
            ? TackColors.line2
            : _pressed
                ? const Color(0xFFF7BB56)
                : TackColors.amber;
        foreground = enabled ? TackColors.ink : TackColors.muted;
    }

    final child = widget.loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                widget.icon!,
                const SizedBox(width: TackSpace.sm),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TackText.button.copyWith(
                    color: foreground,
                    fontSize: v == TackButtonVariant.ghost ? 16 : 17,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: TackMotion.fast,
          curve: TackMotion.curve,
          width: widget.fullWidth ? double.infinity : null,
          height: height,
          padding: widget.fullWidth
              ? null
              : const EdgeInsets.symmetric(horizontal: TackSpace.xl),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: border,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// The tracker's floating action button: 58px, offset above the bottom nav.
class TackFab extends StatelessWidget {
  const TackFab({super.key, required this.onPressed, required this.child, this.semanticLabel});

  final VoidCallback onPressed;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 58,
          width: 58,
          decoration: const BoxDecoration(
            color: TackColors.maroon,
            shape: BoxShape.circle,
            boxShadow: TackShadow.fab,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
