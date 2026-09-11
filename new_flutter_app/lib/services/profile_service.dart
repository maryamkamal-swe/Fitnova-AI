import '../core/constants.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

/// Service managing user profile retrieval and updates.
class ProfileService {
  final ApiClient _apiClient;

  ProfileService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Fetches the authenticated user's profile from GET /profile.
  Future<UserProfile> getProfile() async {
    final response = await _apiClient.get(
      AppConstants.profileEndpoint,
      requiresAuth: true,
    );

    if (response is! Map<String, dynamic>) {
      throw const ApiException(
        message: 'Invalid profile response received from server.',
      );
    }

    return UserProfile.fromJson(response);
  }

  /// Updates the user's profile via PUT /profile.
  Future<UserProfile> updateProfile(UserProfile profile) async {
    final response = await _apiClient.put(
      AppConstants.profileEndpoint,
      body: profile.toJson(),
      requiresAuth: true,
    );

    if (response is! Map<String, dynamic>) {
      throw const ApiException(
        message: 'Invalid profile update response received from server.',
      );
    }

    // The backend currently returns a success message for profile updates.
    if (response.containsKey('message')) return profile;
    return UserProfile.fromJson(response);
  }

  Future<HealthMetrics> getHealthMetrics() async {
    final response = await _apiClient.get(
      AppConstants.healthMetricsEndpoint,
      requiresAuth: true,
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid health metrics response.');
    }
    return HealthMetrics.fromJson(response);
  }

  Future<void> deleteProfile() async {
    await _apiClient.delete(AppConstants.profileEndpoint, requiresAuth: true);
  }
}
