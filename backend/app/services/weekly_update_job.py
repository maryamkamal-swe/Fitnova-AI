
"""
Runs on a schedule (e.g. APScheduler cron, or a Celery beat task -- wire
whichever your deployment already uses). It does NOT introduce new AI logic;
it reuses the exact same generate_workout_plan / generate_weekly_meal_plan
functions the 'Generate' button calls, just with progress data folded in.

NOTE: the progress_logs query below assumes a document shape of
{ "user_id": ..., "metric": "weight", "value": <float>, "date": <datetime> }.
Adjust field names here to match your actual models/progress.py once shared.
"""
from bson import ObjectId
from typing import Optional

from app.models.workout import WorkoutPlanRequest, WorkoutLocation
from app.models.meal import MealPlanRequest
from app.models.user import FitnessGoal, Gender
from app.services.workout_planner_service import generate_workout_plan
from app.services.meal_planner_service import generate_weekly_meal_plan
from app.services.calorie_service import adjust_target_for_weight_trend


async def get_weekly_avg_weight_change(db, user_id: str) -> Optional[float]:
    """
    Pulls the last 14 days of weight entries from progress tracking and
    returns the change between this week's average and last week's average.
    Pure aggregation -- no AI.
    """
    cursor = db.progress.find(
        {"user_id": user_id, "weight": {"$ne": None}}
    ).sort("date", -1).limit(14)
    entries = [doc async for doc in cursor]

    if len(entries) < 14:
        cursor = db.progress_logs.find(
            {"user_id": user_id, "metric": "weight"}
        ).sort("date", -1).limit(14)
        entries = [doc async for doc in cursor]

    if len(entries) < 14:
        return None

    weights = [
        doc["weight"] if doc.get("weight") is not None else doc.get("value")
        for doc in entries
    ]
    if any(w is None for w in weights):
        return None

    this_week = weights[:7]
    last_week = weights[7:14]

    avg_this_week = sum(this_week) / len(this_week)
    avg_last_week = sum(last_week) / len(last_week)

    return avg_this_week - avg_last_week


async def run_weekly_updates_for_user(db, user_id: str, default_location: WorkoutLocation, default_days_per_week: int = 3):
    user_doc = await db.users.find_one({"_id": ObjectId(user_id)})
    if not user_doc or "profile" not in user_doc:
        return
    profile = user_doc["profile"]

    # --- Meal plan: log the weight-trend adjustment, then reuse the pipeline ---
    existing_meal_plan = await db.meal_plans.find_one({"user_id": user_id})
    weight_change = await get_weekly_avg_weight_change(db, user_id)

    if existing_meal_plan and weight_change is not None:
        adjusted_target, reason = adjust_target_for_weight_trend(
            current_target=existing_meal_plan["daily_calorie_target"],
            weekly_avg_weight_change_kg=weight_change,
            fitness_goal=FitnessGoal(profile["fitness_goal"]),
            gender=Gender(profile["gender"]),
        )
        # This adjustment is deterministic and can be surfaced to the user via
        # a notification (see models/notification.py). The generation call below
        # recomputes from profile.weight, so keep weight_kg/entries current via
        # your progress-tracking feature for the two numbers to stay in sync.
        await db.meal_plan_adjustments.insert_one({
            "user_id": user_id, "new_target": adjusted_target, "reason": reason,
        })

    meal_req = MealPlanRequest(user_id=user_id, cuisine="desi")
    await generate_weekly_meal_plan(db, meal_req, source="weekly_auto_update")

    # --- Workout plan: reuse the pipeline as-is ---
    workout_req = WorkoutPlanRequest(
        user_id=user_id,
        location=default_location,
        days_per_week=default_days_per_week,
    )
    await generate_workout_plan(db, workout_req, source="weekly_auto_update")


async def run_weekly_updates_for_all_users(db, default_location: WorkoutLocation = WorkoutLocation.HOME):
    async for user in db.users.find({}, {"_id": 1}):
        await run_weekly_updates_for_user(db, str(user["_id"]), default_location)

