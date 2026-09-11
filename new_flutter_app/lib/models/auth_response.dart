/// Model representing the authentication token response from the backend.
class AuthResponse {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;

  const AuthResponse({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'bearer',
  });

  /// Factory constructor to parse AuthResponse from JSON map.
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'] ?? json['accessToken'];
    if (token == null || token.toString().trim().isEmpty) {
      throw const FormatException(
          'The server returned an invalid login response.');
    }

    return AuthResponse(
      accessToken: token.toString(),
      refreshToken: (json['refresh_token'] ?? json['refreshToken'])?.toString(),
      tokenType:
          (json['token_type'] ?? json['tokenType'] ?? 'bearer').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      'token_type': tokenType,
    };
  }
}
