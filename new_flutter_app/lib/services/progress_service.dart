import '../core/constants.dart';
import '../models/progress_entry.dart';
import '../models/progress_stats.dart';
import 'api_client.dart';

class ProgressService {
  final ApiClient _apiClient;

  ProgressService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<ProgressEntry> logProgress(ProgressEntry entry) async {
    final response = await _apiClient.post(
      AppConstants.progressEndpoint,
      body: entry.toJson(),
      requiresAuth: true,
    );
    return _entryFromResponse(response);
  }

  Future<ProgressEntry?> getTodayProgress() async {
    try {
      final response = await _apiClient.get(
        AppConstants.progressTodayEndpoint,
        requiresAuth: true,
      );
      return _entryFromResponse(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ProgressEntry>> getProgressHistory({
    DateTime? startDate,
    DateTime? endDate,
    int skip = 0,
    int limit = 30,
  }) async {
    final response = await _apiClient.get(
      AppConstants.progressHistoryEndpoint,
      requiresAuth: true,
      queryParameters: {
        if (startDate != null) 'start_date': _dateOnly(startDate),
        if (endDate != null) 'end_date': _dateOnly(endDate),
        'skip': skip,
        'limit': limit,
      },
    );
    final values = response is List
        ? response
        : response is Map<String, dynamic>
            ? (response['items'] ??
                response['data'] ??
                response['progress'] ??
                [])
            : [];
    return (values as List)
        .whereType<Map<String, dynamic>>()
        .map(ProgressEntry.fromJson)
        .toList();
  }

  Future<ProgressStats> getProgressStats({int days = 30}) async {
    final response = await _apiClient.get(
      AppConstants.progressStatsEndpoint,
      requiresAuth: true,
      queryParameters: {'days': days},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid progress stats response.');
    }
    return ProgressStats.fromJson(response);
  }

/// Log water intake hydration entry
  Future<double> logHydration(double addedAmount, {required String date}) async {
    final response = await _apiClient.post(
      '/api/v1/progress/hydration',
      body: {'added_amount': addedAmount, 'date': date},
      requiresAuth: true,
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid hydration response.');
    }

    final liters = response['liters'];
    if (liters is! num) {
      throw const ApiException(message: 'Invalid hydration total.');
    }
    return liters.toDouble();
  }

  Future<ProgressEntry> logCaloriesBurned(
      int calories, {required String date}) async {
    final response = await _apiClient.post(
      '${AppConstants.progressEndpoint}/calories-burned',
      body: {'calories': calories, 'date': date},
      requiresAuth: true,
    );
    return _entryFromResponse(response);
  }

  /// Get today's hydration entry
  Future<Map<String, dynamic>> getTodayHydration({required String date}) async {
    final response = await _apiClient.get(
      '/api/v1/progress/hydration/today',
      requiresAuth: true,
      queryParameters: {'date': date},
    );
    if (response is! Map<String, dynamic>) {
      return {'liters': 0, 'date': ''};
    }
    return response;
  }
  Future<List<Map<String, dynamic>>> getWeightChartData({int days = 30}) =>
      _getChart(AppConstants.progressWeightChartEndpoint, days);

  Future<List<Map<String, dynamic>>> getCaloriesChartData({int days = 30}) =>
      _getChart(AppConstants.progressCaloriesChartEndpoint, days);

  Future<ProgressEntry> updateProgress(String id, ProgressEntry entry) async {
    final response = await _apiClient.put(
      '${AppConstants.progressEndpoint}/$id',
      body: entry.toJson(),
      requiresAuth: true,
    );
    return _entryFromResponse(response);
  }

  Future<void> deleteProgress(String id) async {
    await _apiClient.delete('${AppConstants.progressEndpoint}/$id',
        requiresAuth: true);
  }

  Future<List<Map<String, dynamic>>> _getChart(
      String endpoint, int days) async {
    final response = await _apiClient.get(
      endpoint,
      requiresAuth: true,
      queryParameters: {'days': days},
    );
    final values = response is List
        ? response
        : response is Map<String, dynamic>
            ? (response['data'] ??
                response['items'] ??
                response['points'] ??
                [])
            : [];
    return (values as List).whereType<Map<String, dynamic>>().toList();
  }

  ProgressEntry _entryFromResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      final data = response['progress'] is Map<String, dynamic>
          ? response['progress'] as Map<String, dynamic>
          : response;
      return ProgressEntry.fromJson(data);
    }
    throw const ApiException(message: 'Invalid progress response received.');
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
