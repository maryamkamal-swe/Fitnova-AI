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

  Future<List<Map<String, dynamic>>> getFoodLogs({required String date}) async {
    final response = await _apiClient.get(
      '/api/v1/meal-plans/food-log',
      requiresAuth: true,
      queryParameters: {'date': date},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid food log response.');
    }
    final values = response['foods'];
    return values is List
        ? values.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
  }
  Future<Map<String, dynamic>> logFoodEntry(
    String foodName,
    int? calories, {
    String meal = 'snack',
    String? foodId,
    double servingGrams = 100,
    double servings = 1,
    String? date,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/meal-plans/food-log',
      requiresAuth: true,
      body: {
        'food_name': foodName,
        if (calories != null) 'calories': calories,
        'meal_type': meal,
        if (foodId != null && foodId.isNotEmpty) 'food_id': foodId,
        'serving_grams': servingGrams,
        'servings': servings,
        'date': date ?? _dateOnly(DateTime.now()),
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid food log response.');
    }

    return response;
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

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
