import '../core/constants.dart';
import '../models/auth_response.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// Service managing authentication workflows (login, registration, logout, session state).
class OtpSendResult {
  final bool autoVerified;
  final bool delivered;
  final String? developmentCode;
  final String message;

  const OtpSendResult({
    required this.autoVerified,
    required this.delivered,
    this.developmentCode,
    required this.message,
  });

  factory OtpSendResult.fromJson(dynamic json) {
    final data = json is Map<String, dynamic> ? json : <String, dynamic>{};
    return OtpSendResult(
      autoVerified: data['auto_verified'] == true,
      delivered: data['delivered'] == true,
      developmentCode: data['development_code'] as String?,
      message: (data['message'] as String?) ??
          'A verification code is ready for this email.',
    );
  }
}

class AuthService {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthService({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
  })  : _tokenStorage = tokenStorage ?? TokenStorage(),
        _apiClient = apiClient ?? ApiClient(tokenStorage: tokenStorage);

  /// Authenticates user with email and password.
  /// Securely stores the received JWT and returns the parsed [AuthResponse].
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      AppConstants.loginEndpoint,
      body: {
        'email': email.trim(),
        'password': password,
      },
      requiresAuth: false,
    );

    if (response is! Map<String, dynamic>) {
      throw const ApiException(
        message: 'The server returned an invalid login response.',
      );
    }

    final authResponse = AuthResponse.fromJson(response);
    await _tokenStorage.saveToken(authResponse.accessToken);
    if (authResponse.refreshToken != null) {
      await _tokenStorage.saveRefreshToken(authResponse.refreshToken!);
    }
    return authResponse;
  }

  /// Registers a new account before profile setup.
  /// If the backend returns a token upon registration, it is securely persisted.
  Future<AuthResponse?> register({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      AppConstants.registerEndpoint,
      body: {
        'email': email.trim(),
        'password': password,
      },
      requiresAuth: false,
    );

    if (response is Map<String, dynamic>) {
      // Check if registration response contains a token
      if (response.containsKey('access_token') ||
          response.containsKey('accessToken')) {
        final authResponse = AuthResponse.fromJson(response);
        await _tokenStorage.saveToken(authResponse.accessToken);
        if (authResponse.refreshToken != null) {
          await _tokenStorage.saveRefreshToken(authResponse.refreshToken!);
        }
        return authResponse;
      }
    }

    return null;
  }

  Future<OtpSendResult> sendOtp({required String email}) async {
    final response = await _apiClient.post(
      AppConstants.sendOtpEndpoint,
      body: {'email': email.trim()},
      requiresAuth: false,
    );
    return OtpSendResult.fromJson(response);
  }

  Future<void> verifyOtp({required String email, required String otp}) async {
    await _apiClient.post(
      AppConstants.verifyOtpEndpoint,
      body: {'email': email.trim(), 'otp': otp.trim()},
      requiresAuth: false,
    );
  }

  /// Clears stored credentials and logs out the current user.
  Future<void> logout() async {
    try {
      await _apiClient.post(
        '/api/v1/auth/logout',
        requiresAuth: true,
      );
    } on ApiException {
      // Local sign-out must still succeed if the session is already expired
      // or the server is temporarily unreachable.
    }
    await _tokenStorage.deleteToken();
  }

  Future<AuthResponse> refresh(String refreshToken) async {
    final response = await _apiClient.post(
      AppConstants.refreshEndpoint,
      body: {'refresh_token': refreshToken},
      requiresAuth: false,
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid refresh response.');
    }
    final refreshed = AuthResponse.fromJson(response);
    await _tokenStorage.saveToken(refreshed.accessToken);
    if (refreshed.refreshToken != null) {
      await _tokenStorage.saveRefreshToken(refreshed.refreshToken!);
    }
    return refreshed;
  }

  Future<AuthResponse> refreshStoredSession() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(message: 'No refresh token is available.');
    }
    return refresh(refreshToken);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _apiClient.post(
      AppConstants.changePasswordEndpoint,
      body: {'old_password': oldPassword, 'new_password': newPassword},
      requiresAuth: true,
    );
  }

  /// Checks whether an authenticated session exists.
  Future<bool> isAuthenticated() async {
    return await _tokenStorage.hasToken();
  }

  /// Retrieves the current stored token.
  Future<String?> getCurrentToken() async {
    return await _tokenStorage.getToken();
  }
}
