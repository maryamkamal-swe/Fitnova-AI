import 'dart:convert';

import 'token_storage.dart';

/// Reads the subject from the already persisted JWT without requiring a
/// second identity endpoint. The server remains the source of truth.
class UserIdService {
  final TokenStorage tokenStorage;

  UserIdService({TokenStorage? tokenStorage})
      : tokenStorage = tokenStorage ?? TokenStorage();

  Future<String?> getCurrentUserId() async {
    final token = await tokenStorage.getToken();
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      return payload is Map && payload['sub'] != null
          ? payload['sub'].toString()
          : null;
    } catch (_) {
      return null;
    }
  }
}
