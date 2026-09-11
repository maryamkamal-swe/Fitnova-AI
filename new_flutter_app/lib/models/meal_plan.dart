class MealPlanItem {
  final String foodId;
  final String foodName;
  final double portionGrams;
  final double? calories;

  const MealPlanItem({
    required this.foodId,
    required this.foodName,
    required this.portionGrams,
    this.calories,
  });

  factory MealPlanItem.fromJson(Map<String, dynamic> json) => MealPlanItem(
        foodId: (json['food_id'] ?? json['foodId'] ?? '').toString(),
        foodName: (json['food_name'] ?? json['foodName'] ?? 'Food').toString(),
        portionGrams: _number(json['portion_grams'] ?? json['portionGrams']),
        calories: _nullableNumber(json['calories']),
      );
}

class MealPlanDay {
  final String dayLabel;
  final List<MealPlanItem> breakfast;
  final List<MealPlanItem> lunch;
  final List<MealPlanItem> dinner;
  final List<MealPlanItem> snacks;
  final String? note;

  const MealPlanDay({
    required this.dayLabel,
    this.breakfast = const [],
    this.lunch = const [],
    this.dinner = const [],
    this.snacks = const [],
    this.note,
  });

  factory MealPlanDay.fromJson(Map<String, dynamic> json) => MealPlanDay(
        dayLabel: (json['day_label'] ?? json['dayLabel'] ?? 'Day').toString(),
        breakfast: _items(json['breakfast']),
        lunch: _items(json['lunch']),
        dinner: _items(json['dinner']),
        snacks: _items(json['snacks']),
        note: json['note']?.toString(),
      );
}

class WeeklyMealPlan {
  final List<MealPlanDay> days;
  final String weeklySummary;

  const WeeklyMealPlan({this.days = const [], this.weeklySummary = ''});

  factory WeeklyMealPlan.fromJson(Map<String, dynamic> json) => WeeklyMealPlan(
        days: _maps(json['days']).map(MealPlanDay.fromJson).toList(),
        weeklySummary:
            (json['weekly_summary'] ?? json['weeklySummary'] ?? '').toString(),
      );
}

class MealPlan {
  final String userId;
  final double dailyCalorieTarget;
  final Map<String, dynamic> mealCalorieSplit;
  final WeeklyMealPlan plan;
  final String generatedAt;
  final String source;

  const MealPlan({
    required this.userId,
    required this.dailyCalorieTarget,
    required this.mealCalorieSplit,
    required this.plan,
    required this.generatedAt,
    required this.source,
  });

  factory MealPlan.fromJson(Map<String, dynamic> json) => MealPlan(
        userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
        dailyCalorieTarget:
            _number(json['daily_calorie_target'] ?? json['dailyCalorieTarget']),
        mealCalorieSplit: json['meal_calorie_split'] is Map
            ? Map<String, dynamic>.from(json['meal_calorie_split'] as Map)
            : const {},
        plan: WeeklyMealPlan.fromJson(json['plan'] is Map<String, dynamic>
            ? json['plan'] as Map<String, dynamic>
            : const {}),
        generatedAt:
            (json['generated_at'] ?? json['generatedAt'] ?? '').toString(),
        source: (json['source'] ?? '').toString(),
      );
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

double? _nullableNumber(dynamic value) {
  if (value == null) return null;
  return _number(value);
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : const [];

List<MealPlanItem> _items(dynamic value) =>
    _maps(value).map(MealPlanItem.fromJson).toList();
