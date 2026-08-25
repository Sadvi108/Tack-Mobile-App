import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/auth_controller.dart';
import '../data/validators.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = AuthValidators.email(_email.text));
    if (_error != null) return;
    await ref.read(authControllerProvider.notifier).sendReset(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return TackScaffold(
      header: TackHeader(
        title: 'Reset your password',
        onBack: () => context.go(Routes.login),
      ),
      pinnedCta: TackButton(
        'Send the link',
        loading: auth.busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the email you signed up with. We will send you a link to set a new password.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.xl),
          TackTextField(
            label: 'Email address',
            hint: 'you@example.com',
            controller: _email,
            errorText: _error,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _submit(),
          ),
          if (auth.notice != null) ...[
            const SizedBox(height: TackSpace.lg),
            TackCard(
              background: TackColors.tealTint,
              compact: true,
              child: Text(
                auth.notice!,
                style: TackText.body.copyWith(color: TackColors.tealText),
              ),
            ),
          ],
          if (auth.failure != null) ...[
            const SizedBox(height: TackSpace.lg),
            TackErrorState(body: auth.failure!.message),
          ],
        ],
      ),
    );
  }
}

/// Reached from the emailed link. By the time this screen renders, Supabase has
/// already exchanged the code for a session, so it only needs a new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _passwordError = AuthValidators.password(_password.text);
      _confirmError = _confirm.text == _password.text
          ? null
          : 'The two passwords do not match.';
    });
    if (_passwordError != null || _confirmError != null) return;

    final ok = await ref
        .read(authControllerProvider.notifier)
        .updatePassword(_password.text);
    if (!mounted) return;
    if (ok) {
      TackToast.show(context, message: 'Your password is updated.');
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return TackScaffold(
      header: const TackHeader(title: 'Set a new password'),
      pinnedCta: TackButton(
        'Save password',
        loading: auth.busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick something you have not used before.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.xl),
          TackTextField(
            label: 'New password',
            hint: 'At least 8 characters',
            controller: _password,
            errorText: _passwordError,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'Type it again',
            controller: _confirm,
            errorText: _confirmError,
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          if (auth.failure != null) ...[
            const SizedBox(height: TackSpace.lg),
            Text(auth.failure!.message, style: TackText.fieldError),
          ],
        ],
      ),
    );
  }
}
