import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/auth_controller.dart';
import '../data/validators.dart';
import '../data/oauth_provider.dart';
import 'google_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = AuthValidators.email(_email.text);
      _passwordError = AuthValidators.existingPassword(_password.text);
    });
    if (_emailError != null || _passwordError != null) return;
    await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    // A successful sign-in flips the router's redirect; nothing to do here.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return TackScaffold(
      padBody: false,
      scrollable: false,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TackSpace.screenWide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TackSpace.sm),
            const TackWordmark(),
            const SizedBox(height: TackSpace.xl),
            Text('Welcome back', style: TackText.screenTitle),
            const SizedBox(height: TackSpace.xl),

            GoogleSignInButton(
              label: 'Log in with Google',
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
            ),
            const SizedBox(height: TackSpace.row),
            TackTextField(
              hint: 'Password',
              controller: _password,
              errorText: _passwordError,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
            ),

            if (auth.failure != null) ...[
              const SizedBox(height: TackSpace.sm),
              Text(auth.failure!.message, style: TackText.fieldError),
            ],

            const SizedBox(height: TackSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TackButton.ghost(
                'Forgot password?',
                fullWidth: false,
                onPressed: () => context.go(Routes.forgotPassword),
              ),
            ),
            const SizedBox(height: TackSpace.sm),
            TackButton('Log in', loading: auth.busy, onPressed: _submit),

            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: () => context.go(Routes.signup),
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: TackSpace.tapTarget,
                  ),
                  child: Center(
                    child: Text.rich(
                      TextSpan(
                        text: 'New here? ',
                        style: TackText.meta.copyWith(fontSize: 15),
                        children: [
                          TextSpan(
                            text: 'Create an account',
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
          ],
        ),
      ),
    );
  }
}
