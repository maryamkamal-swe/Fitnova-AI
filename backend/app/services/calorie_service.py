"""
Everything in this file is plain arithmetic on purpose.
Calorie math must never be delegated to the LLM -- it needs to be exact,
auditable, and consistent every time it runs.
"""
from app.models.user import ActivityLevel, FitnessGoal, Gender

ACTIVITY_MULTIPLIERS = {
    ActivityLevel.SEDENTARY: 1.2,
    ActivityLevel.LIGHT: 1.375,
    ActivityLevel.MODERATE: 1.55,
    ActivityLevel.ACTIVE: 1.725,
    ActivityLevel.VERY_ACTIVE: 1.9,
}

# ENDURANCE and FLEXIBILITY aren't primarily about a calorie surplus/deficit,
# so they're treated like maintenance for calorie purposes.
GOAL_CALORIE_ADJUSTMENT = {
    FitnessGoal.WEIGHT_LOSS: -500,
    FitnessGoal.MUSCLE_GAIN: +300,
    FitnessGoal.MAINTENANCE: 0,
    FitnessGoal.ENDURANCE: 0,
    FitnessGoal.FLEXIBILITY: 0,
}

# % of daily calories per meal
MEAL_SPLIT = {
    "breakfast": 0.25,
    "lunch": 0.35,
    "dinner": 0.30,
    "snacks": 0.10,
}

# Hard floor below which auto-adjustment never pushes calories, regardless
# of goal -- surfaces a "talk to a professional" note instead.
SAFE_MINIMUM_CALORIES = {
    Gender.MALE: 1500,
    Gender.FEMALE: 1200,
    Gender.OTHER: 1350,  # conservative midpoint until a more specific value is known
}


def calculate_bmr(weight: float, height: float, age: int, gender: Gender | str) -> float:
    """Calculate BMR consistently for all profile and meal-plan consumers."""
    if not isinstance(gender, Gender):
        gender = Gender(str(gender).lower())
    base = 10 * weight + 6.25 * height - 5 * age
    if gender == Gender.MALE:
        return round(base + 5, 2)
    if gender == Gender.FEMALE:
        return round(base - 161, 2)
    return round(base - 78, 2)


def calculate_tdee(bmr: float, activity_level: ActivityLevel) -> float:
    return bmr * ACTIVITY_MULTIPLIERS[activity_level]


def calculate_daily_target(
    weight: float, height: float, age: int, gender: Gender,
    activity_level: ActivityLevel, fitness_goal: FitnessGoal,
) -> float:
    bmr = calculate_bmr(weight, height, age, gender)
    tdee = calculate_tdee(bmr, activity_level)
    target = tdee + GOAL_CALORIE_ADJUSTMENT[fitness_goal]
    return max(target, SAFE_MINIMUM_CALORIES[gender])


def split_into_meals(daily_calories: float) -> dict:
    return {meal: round(daily_calories * pct) for meal, pct in MEAL_SPLIT.items()}


def calculate_food_nutrition(
    food: dict,
    serving_grams: float,
    servings: float = 1,
) -> dict:
    """Calculate canonical calories and macros for a reference-food serving."""
    grams = serving_grams * servings
    if grams <= 0:
        raise ValueError("Serving size must be greater than zero")
    factor = grams / 100
    return {
        "calories": round(float(food.get("calories_per_100g") or 0) * factor, 2),
        "protein_g": round(float(food.get("protein_g_per_100g") or 0) * factor, 2),
        "carbs_g": round(float(food.get("carbs_g_per_100g") or 0) * factor, 2),
        "fat_g": round(float(food.get("fat_g_per_100g") or 0) * factor, 2),
        "serving_grams": round(grams, 2),
    }


def adjust_target_for_weight_trend(
    current_target: float,
    weekly_avg_weight_change_kg: float,
    fitness_goal: FitnessGoal,
    gender: Gender,
) -> tuple[float, str]:
    """
    Rolling 7-day-average based adjustment. Returns (new_target, reason).
    Rates are deliberately conservative and industry-standard (~0.3-0.7 kg/week).
    """
    reason = "No change -- progress is on track."
    new_target = current_target

    if fitness_goal == FitnessGoal.WEIGHT_LOSS:
        if weekly_avg_weight_change_kg > -0.2:
            new_target = current_target * 0.93
            reason = "Weight loss has stalled -- reducing target by ~7%."
        elif weekly_avg_weight_change_kg < -0.9:
            new_target = current_target * 1.05
            reason = "Losing faster than recommended -- increasing target slightly."

    elif fitness_goal == FitnessGoal.MUSCLE_GAIN:
        if weekly_avg_weight_change_kg < 0.1:
            new_target = current_target * 1.07
            reason = "Weight gain has stalled -- increasing target by ~7%."
        elif weekly_avg_weight_change_kg > 0.7:
            new_target = current_target * 0.95
            reason = "Gaining faster than recommended -- reducing target slightly."

    new_target = max(new_target, SAFE_MINIMUM_CALORIES[gender])
    return round(new_target), reason
