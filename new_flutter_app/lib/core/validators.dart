/// Reusable form validation helpers for FitNova AI.
class Validators {
  // Regex for standard email format validation
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  // Regexes for password complexity rules
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSpecialChar =
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]');

  /// Validates a user's display name.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name.';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters.';
    }
    return null;
  }

  /// Validates an email address.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address.';
    }
    final trimmed = value.trim();
    if (!_emailRegExp.hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  /// Validates a password against security rules.
  /// Minimum 8 characters, at least one uppercase, one lowercase, one digit, and one special character.
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password.';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!_hasUppercase.hasMatch(value)) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!_hasLowercase.hasMatch(value)) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!_hasDigit.hasMatch(value)) {
      return 'Password must contain at least one number.';
    }
    if (!_hasSpecialChar.hasMatch(value)) {
      return 'Password must contain at least one special character.';
    }
    return null;
  }

  /// Validates that confirm password matches the initial password.
  static String? validateConfirmPassword(
      String? confirmPassword, String? password) {
    if (confirmPassword == null || confirmPassword.isEmpty) {
      return 'Please confirm your password.';
    }
    if (confirmPassword != password) {
      return 'Passwords do not match.';
    }
    return null;
  }
}
