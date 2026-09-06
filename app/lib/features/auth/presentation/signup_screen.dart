import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/policy_links.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/auth_controller.dart';
import '../data/validators.dart';
import '../data/auth_repository.dart';
import '../data/oauth_provider.dart';
import 'google_button.dart';

/// Sign up.
///
/// This screen must fit 360×640 with no scrolling — measured against the
/// shortest common Android viewport. Everything on it is there because it
/// earns its height: there is no subtitle paragraph, no field labels above the
/// inputs, and no marketing.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _revalidate() {
    if (!_submitted) return;
    setState(() {
      _emailError = AuthValidators.email(_email.text);
      _passwordError = AuthValidators.password(_password.text);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _emailError = AuthValidators.email(_email.text);
      _passwordError = AuthValidators.password(_password.text);
    });
    if (_emailError != null || _passwordError != null) return;

    final outcome = await ref
        .read(authControllerProvider.notifier)
        .signUp(email: _email.text, password: _password.text);
    if (!mounted) return;

    switch (outcome) {
      case SignUpOutcome.confirmationSent:
        TackToast.show(
          context,
          message: 'Check your inbox. We sent a link to confirm your email.',
        );
        context.go(Routes.login);
      case SignUpOutcome.signedIn:
        // Confirmation is off for this project; the router takes it from here.
        break;
      case SignUpOutcome.alreadyRegistered:
        // Not an error the student caused, so it is offered as a next step
        // rather than left as a red line under the field.
        TackToast.show(
          context,
          message: 'That email already has an account.',
          kind: TackToastKind.info,
          actionLabel: 'Log in',
          onAction: () => context.go(Routes.login),
        );
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    // The type sizes here are an accessibility floor, not a preference, so
    // when a student turns their text size up it is the spacing that yields,
    // never the text. `app.dart` caps the scale at 1.3; at that cap this gives
    // back more than the height the 16px body line costs, so the screen keeps
    // its no-scroll promise instead of overflowing by a couple of pixels.
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final gap = textScale > 1 ? 1 / textScale : 1.0;

    return TackScaffold(
      padBody: false,
      scrollable: false,
      background: TackColors.sailWhite,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TackSpace.screenWide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: TackSpace.sm * gap),
            const TackWordmark(),
            SizedBox(height: TackSpace.lg * gap),
            Text('Create your account', style: TackText.screenTitle),
            SizedBox(height: TackSpace.xs * gap),
            Text('Free for every student.', style: TackText.bodyMuted),
            SizedBox(height: TackSpace.lg * gap),

            GoogleSignInButton(
              busy: auth.busy,
              onPressed: () => ref
                  .read(authControllerProvider.notifier)
                  .signInWith(TackOAuthProvider.google),
            ),
            SizedBox(height: TackSpace.row * gap),
            SecondaryProviderRow(
              busy: auth.busy,
              onPressed: (provider) => ref
                  .read(authControllerProvider.notifier)
                  .signInWith(provider),
            ),
            SizedBox(height: TackSpace.md * gap),
            const TackOrDivider(),
            SizedBox(height: TackSpace.md * gap),

            TackTextField(
              hint: 'Email address',
              controller: _email,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => _revalidate(),
            ),
            SizedBox(height: TackSpace.row * gap),
            TackTextField(
              hint: 'Password, at least 8 characters',
              controller: _password,
              errorText: _passwordError,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => _revalidate(),
              onSubmitted: (_) => _submit(),
            ),

            if (auth.failure != null) ...[
              SizedBox(height: TackSpace.sm * gap),
              Text(auth.failure!.message, style: TackText.fieldError),
            ],

            SizedBox(height: TackSpace.md * gap),
            TackButton(
              'Create account',
              loading: auth.busy,
              onPressed: _submit,
            ),

            const Spacer(),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: TackIcon(
                    TackIcons.shield,
                    size: 17,
                    color: TackColors.muted,
                  ),
                ),
                const SizedBox(width: TackSpace.sm),
                // Consent belongs at the moment of consent, but this screen
                // must fit 360x640 with no scrolling and has no spare height —
                // a separate line overflowed it by 35px. So the links join the
                // privacy promise that was already here, which is the same
                // subject anyway.
                const Expanded(child: PolicyNote()),
              ],
            ),
            SizedBox(height: TackSpace.xs * gap),
            Center(
              child: Semantics(
                button: true,
                child: GestureDetector(
                  onTap: () => context.go(Routes.login),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: TackSpace.tapTarget,
                    ),
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TackText.meta.copyWith(fontSize: 15),
                          children: [
                            TextSpan(
                              text: 'Log in',
                              style: TackText.meta.copyWith(
                                fontSize: 15,
                                color: TackColors.maroonText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
