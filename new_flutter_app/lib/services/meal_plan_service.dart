import '../core/constants.dart';
import '../models/meal_plan.dart';
import 'api_client.dart';

class MealPlanService {
  final ApiClient _apiClient;

  MealPlanService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<MealPlan> generate({String cuisine = 'desi', String? userId}) async {
    final response = await _apiClient.post(
      AppConstants.mealPlanGenerateEndpoint,
      requiresAuth: true,
      body: {
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
        'cuisine': cuisine,
      },
    );
    return _parse(response);
  }

  Future<MealPlan> getCurrent({String? userId}) async {
    final response = await _apiClient.get(
      '${AppConstants.mealPlanEndpoint}/current',
      requiresAuth: true,
    );
    return _parse(response);
  }
  Future<void> logFoodEntry(
    String foodName,
    int calories, {
    String meal = 'snack',
  }) async {
    await _apiClient.post(
      '/api/v1/meal-plans/food-log',
      requiresAuth: true,
      body: {
        'food_name': foodName,
        'calories': calories,
        'meal_type': meal,
      },
    );
  }

  Future<void> logRecipePreparation(
    String recipeId,
    List<int> stepsCompleted,
    int timeSpentMinutes,
  ) async {
    await _apiClient.post(
      '/api/v1/meal-plans/recipe-preparation',
      requiresAuth: true,
      body: {
        'recipe_id': recipeId,
        'steps_completed': stepsCompleted,
        'time_spent_minutes': timeSpentMinutes,
      },
    );
  }

  MealPlan _parse(dynamic response) {
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid meal plan response.');
    }
    return MealPlan.fromJson(response);
  }
}
