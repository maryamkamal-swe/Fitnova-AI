import '../core/constants.dart';
import '../models/workout_plan.dart';
import 'api_client.dart';

class WorkoutPlanService {
  final ApiClient _apiClient;

  WorkoutPlanService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<WorkoutPlan> generate({
    required String location,
    int daysPerWeek = 3,
    List<String> excludedMuscleGroups = const [],
    String? userId,
  }) async {
    final response = await _apiClient.post(
      AppConstants.workoutPlanGenerateEndpoint,
      requiresAuth: true,
      body: {
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
        'location': location,
        'days_per_week': daysPerWeek,
        'excluded_muscle_groups': excludedMuscleGroups,
      },
    );
    return _parse(response);
  }

  Future<WorkoutPlan> getCurrent({String? userId}) async {
    final response = await _apiClient.get(
      '${AppConstants.workoutPlanEndpoint}/current',
      requiresAuth: true,
    );
    return _parse(response);
  }

  WorkoutPlan _parse(dynamic response) {
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid workout plan response.');
    }
    return WorkoutPlan.fromJson(response);
  }
}
