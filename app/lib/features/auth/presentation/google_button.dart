import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import 'google_mark.dart';

/// The prominent sign-in option. Most students already have a Google account,
/// and every tap saved here is a student who does not abandon sign-up.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'Continue with Google',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.buttonAll,
            border: Border.all(color: TackColors.line2, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const GoogleMark(size: 20),
              const SizedBox(width: TackSpace.md),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TackText.button.copyWith(color: TackColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "or use email" with a rule either side.
class TackOrDivider extends StatelessWidget {
  const TackOrDivider({super.key, this.label = 'or use email'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: TackDivider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.md),
          child: Text(label, style: TackText.meta.copyWith(fontSize: 13.5)),
        ),
        const Expanded(child: TackDivider()),
      ],
    );
  }
}
