import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../data/auth_repository.dart';
import '../data/oauth_provider.dart';

/// What an auth screen needs to render: whether a request is in flight, and
/// the last failure if there was one.
class AuthUiState {
  const AuthUiState({this.busy = false, this.failure, this.notice});

  final bool busy;
  final Failure? failure;

  /// A success message that is not an error — "check your inbox", for example.
  final String? notice;

  AuthUiState copyWith({
    bool? busy,
    Failure? failure,
    String? notice,
    bool clear = false,
  }) => AuthUiState(
    busy: busy ?? this.busy,
    failure: clear ? null : (failure ?? this.failure),
    notice: clear ? null : (notice ?? this.notice),
  );
}

class AuthController extends Notifier<AuthUiState> {
  @override
  AuthUiState build() => const AuthUiState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<bool> _run(Future<void> Function() action, {String? notice}) async {
    state = const AuthUiState(busy: true);
    try {
      await action();
      state = AuthUiState(notice: notice);
      return true;
    } catch (e) {
      state = AuthUiState(failure: Failure.from(e));
      return false;
    }
  }

  /// Signs up, and reports what actually happened rather than always claiming
  /// an email is on its way.
  Future<SignUpOutcome?> signUp({
    required String email,
    required String password,
  }) async {
    state = const AuthUiState(busy: true);
    try {
      final outcome = await _repo.signUpWithEmail(
        email: email,
        password: password,
      );
      state = switch (outcome) {
        SignUpOutcome.confirmationSent => const AuthUiState(
          notice: 'Check your inbox. We sent a link to confirm your email.',
        ),
        SignUpOutcome.signedIn => const AuthUiState(),
        SignUpOutcome.alreadyRegistered => const AuthUiState(
          failure: Failure(
            'There is already an account with that email. Log in instead, or '
            'reset your password if you have forgotten it.',
          ),
        ),
      };
      return outcome;
    } catch (e) {
      state = AuthUiState(failure: Failure.from(e));
      return null;
    }
  }

  Future<bool> signIn({required String email, required String password}) =>
      _run(() => _repo.signInWithEmail(email: email, password: password));

  Future<bool> signInWith(TackOAuthProvider provider) =>
      _run(() => _repo.signInWithProvider(provider));

  Future<bool> sendReset(String email) => _run(
    () => _repo.sendPasswordReset(email),
    notice: 'Check your inbox. We sent a link to set a new password.',
  );

  Future<bool> updatePassword(String password) => _run(
    () => _repo.updatePassword(password),
    notice: 'Your password is updated.',
  );

  Future<bool> resendConfirmation(String email) => _run(
    () => _repo.resendConfirmation(email),
    notice: 'Sent again. Check your inbox.',
  );

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthUiState();
  }

  void clear() => state = const AuthUiState();
}

final authControllerProvider = NotifierProvider<AuthController, AuthUiState>(
  AuthController.new,
);
