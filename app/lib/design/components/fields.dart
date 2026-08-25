import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../tokens.dart';
import '../typography.dart';

/// The text field. 50–52px tall, 1.5px border, maroon on focus, danger on
/// error with a 13.5px message below.
class TackTextField extends StatefulWidget {
  const TackTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<TackTextField> createState() => _TackTextFieldState();
}

class _TackTextFieldState extends State<TackTextField> {
  late final FocusNode _focus = FocusNode()..addListener(() => setState(() {}));
  late bool _obscured = widget.obscureText;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = hasError
        ? TackColors.danger
        : _focus.hasFocus
        ? TackColors.maroon
        : TackColors.line2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: TackText.fieldLabel),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: TackMotion.fast,
          constraints: BoxConstraints(
            minHeight: widget.maxLines > 1 ? 110 : 52,
          ),
          decoration: BoxDecoration(
            color: widget.enabled ? TackColors.white : TackColors.sailWhite,
            borderRadius: TackRadius.inputAll,
            border: Border.all(color: borderColor, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: widget.maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (widget.prefix != null) ...[
                Padding(
                  padding: EdgeInsets.only(top: widget.maxLines > 1 ? 14 : 0),
                  child: widget.prefix!,
                ),
                const SizedBox(width: TackSpace.sm),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  obscureText: _obscured,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.obscureText ? 1 : widget.maxLines,
                  minLines: widget.minLines,
                  maxLength: widget.maxLength,
                  inputFormatters: widget.inputFormatters,
                  textInputAction: widget.textInputAction,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  autofillHints: widget.autofillHints,
                  cursorColor: TackColors.maroon,
                  style: TackText.body,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: TackText.body.copyWith(color: TackColors.muted),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: widget.maxLines > 1 ? 14 : 15,
                    ),
                  ),
                ),
              ),
              if (widget.obscureText)
                GestureDetector(
                  onTap: () => setState(() => _obscured = !_obscured),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: TackSpace.tapTarget,
                    height: TackSpace.tapTarget,
                    child: Center(
                      child: Text(
                        _obscured ? 'Show' : 'Hide',
                        style: TackText.pill.copyWith(color: TackColors.maroon),
                      ),
                    ),
                  ),
                )
              else if (widget.suffix != null)
                widget.suffix!,
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(widget.errorText!, style: TackText.fieldError),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helperText!,
            style: TackText.meta.copyWith(fontSize: 13.5),
          ),
        ],
      ],
    );
  }
}

/// A select that opens a bottom sheet rather than a dropdown menu — a sheet is
/// reachable with a thumb and a menu is not.
class TackSelectField<T> extends StatelessWidget {
  const TackSelectField({
    super.key,
    this.label,
    required this.hint,
    required this.value,
    required this.valueLabel,
    required this.onTap,
    this.errorText,
    this.enabled = true,
  });

  final String? label;
  final String hint;
  final T? value;
  final String Function(T value) valueLabel;
  final VoidCallback onTap;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: TackText.fieldLabel),
          const SizedBox(height: 6),
        ],
        Semantics(
          button: true,
          label: label ?? hint,
          value: value == null ? null : valueLabel(value as T),
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: enabled ? TackColors.white : TackColors.sailWhite,
                borderRadius: TackRadius.inputAll,
                border: Border.all(
                  color: hasError ? TackColors.danger : TackColors.line2,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value == null ? hint : valueLabel(value as T),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TackText.body.copyWith(
                        color: value == null
                            ? TackColors.muted
                            : TackColors.ink,
                      ),
                    ),
                  ),
                  const TackIcon(
                    TackIcons.chevronDown,
                    size: 20,
                    color: TackColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: TackText.fieldError),
        ],
      ],
    );
  }
}

/// The search field used above chip grids and list filters.
class TackSearchField extends StatelessWidget {
  const TackSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TackTextField(
      hint: hint,
      controller: controller,
      onChanged: onChanged,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      prefix: const TackIcon(
        TackIcons.search,
        size: 20,
        color: TackColors.muted,
      ),
    );
  }
}
