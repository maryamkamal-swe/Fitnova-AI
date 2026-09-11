import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';

/// Secure token storage utility using FlutterSecureStorage.
class TokenStorage {
  final FlutterSecureStorage _storage;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Saves the JWT token securely.
  Future<void> saveToken(String token) async {
    if (token.trim().isEmpty) return;
    try {
      await _storage.write(
        key: AppConstants.tokenStorageKey,
        value: token.trim(),
      );
    } catch (_) {
      // Storage exceptions are caught silently without logging sensitive data
    }
  }

  Future<void> saveRefreshToken(String token) async {
    if (token.trim().isEmpty) return;
    await _storage.write(
      key: AppConstants.refreshTokenStorageKey,
      value: token.trim(),
    );
  }

  /// Retrieves the JWT token, or null if not stored or on error.
  Future<String?> getToken() async {
    try {
      final token = await _storage.read(key: AppConstants.tokenStorageKey);
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: AppConstants.refreshTokenStorageKey);
  }

  /// Deletes the JWT token upon logout or session expiration.
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: AppConstants.tokenStorageKey);
      await _storage.delete(key: AppConstants.refreshTokenStorageKey);
    } catch (_) {
      // Catch storage error safely
    }
  }

  /// Checks if a non-empty JWT token exists in secure storage.
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
