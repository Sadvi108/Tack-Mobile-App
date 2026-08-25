import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/auth_controller.dart';
import '../data/validators.dart';
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

    final ok = await ref
        .read(authControllerProvider.notifier)
        .signUp(email: _email.text, password: _password.text);
    if (!mounted) return;
    if (ok) {
      final notice = ref.read(authControllerProvider).notice;
      if (notice != null) TackToast.show(context, message: notice);
      context.go(Routes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return TackScaffold(
      padBody: false,
      scrollable: false,
      background: TackColors.sailWhite,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TackSpace.screenWide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TackSpace.sm),
            const TackWordmark(),
            const SizedBox(height: TackSpace.lg),
            Text('Create your account', style: TackText.screenTitle),
            const SizedBox(height: TackSpace.xs),
            Text('Free for every student.', style: TackText.bodyMuted),
            const SizedBox(height: TackSpace.lg),

            GoogleSignInButton(
              busy: auth.busy,
              onPressed: () => ref
                  .read(authControllerProvider.notifier)
                  .signInWith(TackOAuthProvider.google),
            ),
            const SizedBox(height: TackSpace.row),
            SecondaryProviderRow(
              busy: auth.busy,
              onPressed: (provider) => ref
                  .read(authControllerProvider.notifier)
                  .signInWith(provider),
            ),
            const SizedBox(height: TackSpace.md),
            const TackOrDivider(),
            const SizedBox(height: TackSpace.md),

            TackTextField(
              hint: 'Email address',
              controller: _email,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => _revalidate(),
            ),
            const SizedBox(height: TackSpace.row),
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
              const SizedBox(height: TackSpace.sm),
              Text(auth.failure!.message, style: TackText.fieldError),
            ],

            const SizedBox(height: TackSpace.md),
            TackButton(
              'Create account',
              loading: auth.busy,
              onPressed: _submit,
            ),

            const Spacer(),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: TackIcon(
                    TackIcons.shield,
                    size: 17,
                    color: TackColors.muted,
                  ),
                ),
                const SizedBox(width: TackSpace.sm),
                Expanded(
                  child: Text(
                    'Your CV and certificates stay private. Only you can see them.',
                    style: TackText.meta.copyWith(fontSize: 13.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TackSpace.xs),
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
                                color: TackColors.maroon,
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
