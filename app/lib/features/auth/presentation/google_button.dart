import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/oauth_provider.dart';
import 'provider_marks.dart';

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
              const ProviderMark(TackOAuthProvider.google),
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

/// Providers enabled for the current release.
///
/// Compact on purpose: the sign-up screen has to fit 360x640 with no scroll,
/// and three full-width buttons would not. Google stays prominent because it
/// is the one most students will use; these are for the ones who will not.
class SecondaryProviderRow extends StatelessWidget {
  const SecondaryProviderRow({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.providers = const [TackOAuthProvider.github],
  });

  final void Function(TackOAuthProvider provider) onPressed;
  final bool busy;
  final List<TackOAuthProvider> providers;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < providers.length; i++) ...[
          if (i > 0) const SizedBox(width: TackSpace.row),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Continue with ${providers[i].label}',
              child: GestureDetector(
                onTap: busy ? null : () => onPressed(providers[i]),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: TackColors.white,
                    borderRadius: TackRadius.buttonAll,
                    border: Border.all(color: TackColors.line2, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ProviderMark(providers[i], size: 19),
                      const SizedBox(width: TackSpace.sm),
                      Flexible(
                        child: Text(
                          providers[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TackText.button.copyWith(
                            color: TackColors.ink,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
