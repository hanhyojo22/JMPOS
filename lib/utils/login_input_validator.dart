class LoginInputValidator {
  const LoginInputValidator._();

  static const int maxUsernameLength = 80;
  static const int maxPasswordLength = 128;

  static final RegExp controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp usernameDeniedCharacters = RegExp(
    r'[\u0000-\u001F\u007F\s]',
  );
  static final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9_]+$');

  static String sanitizeUsername(String value) {
    return value.replaceAll(controlCharacters, '').trim().toLowerCase();
  }

  static String sanitizePassword(String value) {
    return value.replaceAll(controlCharacters, '');
  }

  static bool isEmail(String value) {
    return emailPattern.hasMatch(sanitizeUsername(value));
  }

  static bool isValidUsernameOrEmail(String value) {
    final username = sanitizeUsername(value);
    if (username.length < 3 || username.length > maxUsernameLength) {
      return false;
    }

    return emailPattern.hasMatch(username) ||
        usernamePattern.hasMatch(username);
  }

  static bool isValidPassword(String value) {
    final password = sanitizePassword(value);
    return password.length >= 6 && password.length <= maxPasswordLength;
  }

  static String? validateUsername(String? value) {
    final username = sanitizeUsername(value ?? '');
    final isEmailLogin = emailPattern.hasMatch(username);
    if (username.isEmpty) return 'Please enter your username or email';
    if (username.length < 3) return 'Login must be at least 3 characters';
    if (username.length > maxUsernameLength) return 'Username is too long';
    if (!isEmailLogin && !usernamePattern.hasMatch(username)) {
      return 'Use a username or valid email';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    final password = sanitizePassword(value ?? '');
    if (password.isEmpty) return 'Please enter your password';
    if (password.length > maxPasswordLength) return 'Password is too long';
    return null;
  }

  static String? validateEmail(String? value) {
    final email = sanitizeUsername(value ?? '');
    if (email.isEmpty) return 'Please enter your email';
    if (!emailPattern.hasMatch(email)) return 'Please enter a valid email';
    return null;
  }
}
