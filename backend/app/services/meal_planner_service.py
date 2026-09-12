from datetime import datetime, timezone
import asyncio
import logging
from typing import Optional

from app.models.meal import MealPlanRequest, WeeklyMealPlan, MealPlanResponse, PlannedMealItem
from app.models.user import FitnessGoal, ActivityLevel, Gender
from app.services.user_lookup import get_user_profile
from app.services.calorie_service import (
    calculate_daily_target,
    calculate_food_nutrition,
    split_into_meals,
)
from app.services.food_filter_service import get_candidate_foods, format_food_candidates_for_prompt
from app.services.llm_service import generate_structured

logger = logging.getLogger(__name__)

MEAL_CATEGORIES = ["breakfast", "lunch", "dinner", "snacks"]

SYSTEM_PROMPT = """You are a nutrition planner specializing in South Asian (desi) cuisine. \
You must ONLY use dishes from the candidate list provided for each meal slot -- never invent \
a dish or a food_id that isn't in the list. Every dish must be authentic desi/South Asian food. \
Ensure variety across the week (don't repeat the same dish in the same slot every day). \
Return only the requested JSON structure -- portion_grams can be an approximate starting \
value, the backend will rescale it precisely to hit calorie targets."""


def _build_user_prompt(goal: FitnessGoal, cuisine: str, dietary_preferences: list[str],
                        meal_targets: dict, candidates_by_meal: dict[str, str]) -> str:
    candidates_block = "\n\n".join(
        f"{meal.upper()} candidates (target ~{meal_targets[meal]} kcal):\n{text}"
        for meal, text in candidates_by_meal.items()
    )
    restrictions = ", ".join(dietary_preferences) or "none"
    return f"""
User profile:
- Goal: {goal.value}
- Cuisine: {cuisine}
- Dietary preferences/restrictions: {restrictions}

Daily calorie split target: breakfast {meal_targets['breakfast']} kcal, \
lunch {meal_targets['lunch']} kcal, dinner {meal_targets['dinner']} kcal, \
snacks {meal_targets['snacks']} kcal.

{candidates_block}

Build a full 7-day plan (Monday-Sunday). For each day and each meal slot, pick 1-2 \
dishes from that slot's candidate list ONLY. Vary dish choices across the week.
"""


def _rescale_items(items: list[PlannedMealItem], target_kcal: float, food_lookup: dict[str, dict]) -> list[dict]:
    """
    The LLM picks WHICH dishes go in a meal; this function does the precise
    gram-portion math so the meal's total calories land on target. Pure arithmetic.
    """
    valid_items = [i for i in items if i.food_id in food_lookup]
    if not valid_items:
        return []

    per_item_target = target_kcal / len(valid_items)
    result = []
    for item in valid_items:
        food = food_lookup[item.food_id]
        cal_per_100g = food["calories_per_100g"]
        portion_g = round((per_item_target / cal_per_100g) * 100, 1) if cal_per_100g else 0
        nutrition = calculate_food_nutrition(food, portion_g)
        result.append({
            "food_id": item.food_id,
            "food_name": item.food_name,
            "portion_grams": portion_g,
            "calories": nutrition["calories"],
        })
    return result


def _fallback_plan(
    candidates_by_meal: dict[str, list[dict]], meal_targets: dict[str, float],
) -> WeeklyMealPlan:
    days = []
    for day_number in range(7):
        slots = {}
        for meal in MEAL_CATEGORIES:
            from app.services.food_filter_service import _default_foods

            candidates = candidates_by_meal.get(meal) or _default_foods(
                "snack" if meal == "snacks" else meal, []
            )
            food = candidates[day_number % len(candidates)]
            slots[meal] = [PlannedMealItem(
                food_id=food["id"],
                food_name=food["name"],
                portion_grams=100,
            )]
        days.append({
            "day_label": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day_number],
            **slots,
            "note": "Balanced portions selected from the available reference foods.",
        })
    return WeeklyMealPlan(
        days=days,
        weekly_summary="A balanced weekly plan generated from the available reference foods.",
    )


async def generate_weekly_meal_plan(
    db, req: MealPlanRequest, weekly_avg_weight_change_kg: Optional[float] = None,
    source: str = "generate_button",
    override_calorie_target: Optional[float] = None,
) -> MealPlanResponse:
    if not req.user_id:
        raise ValueError("Authenticated user id is required to generate a meal plan")

    profile = await get_user_profile(db, req.user_id)
    goal = FitnessGoal(profile["fitness_goal"])
    activity_level = ActivityLevel(profile["activity_level"])
    gender = Gender(profile["gender"])
    dietary_preferences = profile.get("dietary_preferences", []) or []

    # 1. Deterministic calorie target (never AI)
    daily_target = (
        override_calorie_target
        if override_calorie_target is not None
        else calculate_daily_target(
            weight=profile["weight"], height=profile["height"], age=profile["age"],
            gender=gender, activity_level=activity_level, fitness_goal=goal,
        )
    )
    meal_targets = split_into_meals(daily_target)

    # 2. Filter candidates per meal slot (no AI)
    candidates_by_meal: dict[str, list[dict]] = {}
    candidates_text_by_meal: dict[str, str] = {}
    food_lookup: dict[str, dict] = {}
    for meal in MEAL_CATEGORIES:
        category = "snack" if meal == "snacks" else meal
        foods = await get_candidate_foods(
            db, cuisine=req.cuisine, category=category, dietary_preferences=dietary_preferences,
        )
        for f in foods:
            food_lookup[f["id"]] = f
        candidates_by_meal[meal] = foods
        candidates_text_by_meal[meal] = format_food_candidates_for_prompt(foods)

    # 3. LLM selects combinations + ensures weekly variety
    try:
        raw_plan: WeeklyMealPlan = await asyncio.to_thread(
            generate_structured,
            SYSTEM_PROMPT,
            _build_user_prompt(
                goal, req.cuisine, dietary_preferences, meal_targets, candidates_text_by_meal
            ),
            WeeklyMealPlan,
        )
    except Exception as exc:
        logger.warning("Structured meal planning failed; using deterministic reference-food fallback: %s", exc)
        raw_plan = _fallback_plan(candidates_by_meal, meal_targets)

    # 4. Refill invalid slots, then rescale every meal precisely in code.
    def refill_slot(items: list[PlannedMealItem], meal: str, day_number: int) -> list[PlannedMealItem]:
        valid_items = [item for item in items if item.food_id in food_lookup]
        if valid_items:
            return valid_items
        candidates = candidates_by_meal.get(meal, [])
        if not candidates:
            from app.services.food_filter_service import _default_foods
            candidates = _default_foods("snack" if meal == "snacks" else meal, dietary_preferences)
            for food in candidates:
                food_lookup.setdefault(food["id"], food)
        if not candidates:
            return []
        food = candidates[day_number % len(candidates)]
        return [PlannedMealItem(
            food_id=food["id"],
            food_name=food["name"],
            portion_grams=100,
        )]

    def rescale_day(day, day_number: int) -> None:
        for meal, target in (
            ("breakfast", meal_targets["breakfast"]),
            ("lunch", meal_targets["lunch"]),
            ("dinner", meal_targets["dinner"]),
            ("snacks", meal_targets["snacks"]),
        ):
            items = refill_slot(getattr(day, meal), meal, day_number)
            setattr(
                day,
                meal,
                [PlannedMealItem(**item) for item in _rescale_items(items, target, food_lookup)],
            )

    for day_number, day in enumerate(raw_plan.days):
        rescale_day(day, day_number)

    response = MealPlanResponse(
        user_id=req.user_id,
        daily_calorie_target=daily_target,
        meal_calorie_split=meal_targets,
        plan=raw_plan,
        generated_at=datetime.now(timezone.utc).isoformat(),
        source=source,
    )

    await db.meal_plans.update_one(
        {"user_id": req.user_id},
        {"$set": response.model_dump()},
        upsert=True,
    )
    return response
