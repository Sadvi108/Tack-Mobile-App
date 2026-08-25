/// Form validation shared by the auth screens.
///
/// Messages are sentence case, plain, and say what to do rather than what the
/// student did wrong.
class AuthValidators {
  const AuthValidators._();

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(v)) return 'That does not look like an email address.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a password.';
    if (v.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  static String? existingPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  static String? fullName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your name.';
    if (v.length < 2) return 'Enter your full name.';
    return null;
  }

  /// Bangladeshi mobile numbers are 10 digits after the +880 prefix and start
  /// with 1. The prefix is locked in the UI, so only the rest is checked here.
  static String? bdPhone(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (v.isEmpty) return 'Enter your phone number.';
    if (v.length != 10 || !v.startsWith('1')) {
      return 'Enter a 10-digit number starting with 1, like 712345678.';
    }
    return null;
  }
}
