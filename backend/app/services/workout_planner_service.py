from datetime import datetime, timezone
import asyncio
import logging

from app.models.workout import WorkoutPlanRequest, WeeklyWorkoutPlan, WorkoutPlanResponse
from app.models.user import FitnessExperience, FitnessGoal
from app.services.user_lookup import get_user_profile
from app.services.exercise_filter_service import (
    get_candidate_exercises, format_exercise_candidates_for_prompt,
)
from app.services.llm_service import generate_structured

logger = logging.getLogger(__name__)

# Simple, proven weekly split templates by days/week.
# The LLM fills each labelled day with real exercises -- it does not invent the split.
SPLIT_TEMPLATES = {
    2: ["Full Body A", "Full Body B"],
    3: ["Push", "Pull", "Legs"],
    4: ["Upper", "Lower", "Push", "Pull"],
    5: ["Push", "Pull", "Legs", "Upper", "Lower"],
    6: ["Push", "Pull", "Legs", "Push", "Pull", "Legs"],
}

SYSTEM_PROMPT = """You are a certified strength coach building a structured weekly \
workout plan. You must ONLY use exercises from the candidate list provided for each \
day -- never invent an exercise or an exercise_id that isn't in the list. \
Match sets/reps/rest to the user's experience level and goal. Keep coaching notes \
short, encouraging, and safety-conscious. Return only the requested JSON structure."""


def _build_user_prompt(
    goal: FitnessGoal, experience: FitnessExperience, req: WorkoutPlanRequest,
    day_labels: list[str], candidates_text: str,
) -> str:
    return f"""
User profile:
- Goal: {goal.value}
- Experience: {experience.value}
- Location: {req.location.value}
- Training days this week: {', '.join(day_labels)}

Candidate exercises (choose ONLY from this list, reuse across days as sensible,
but avoid working the same muscle group on back-to-back days where the split allows):
{candidates_text}

Build one full week: one WorkoutDay entry per label above, each with 4-6 exercises,
appropriate sets/reps/rest for a {experience.value} lifter with a {goal.value} goal.
"""


def _validate_plan(plan: WeeklyWorkoutPlan, candidate_ids: set[str]) -> WeeklyWorkoutPlan:
    """Defensive check: strip out any exercise the LLM hallucinated outside the candidate pool."""
    for day in plan.days:
        day.exercises = [ex for ex in day.exercises if ex.exercise_id in candidate_ids]
    return plan


def _fallback_plan(candidates: list[dict], day_labels: list[str]) -> WeeklyWorkoutPlan:
    if not candidates:
        from app.services.exercise_filter_service import DEFAULT_EXERCISES

        candidates = list(DEFAULT_EXERCISES)
    days = []
    for day_number, label in enumerate(day_labels):
        exercises = []
        for offset in range(min(4, len(candidates))):
            exercise = candidates[(day_number + offset) % len(candidates)]
            exercises.append({
                "exercise_id": exercise["id"],
                "exercise_name": exercise["name"],
                "sets": 3,
                "reps": "8-12",
                "rest_seconds": 60,
                "coaching_note": "Use controlled movement and stop if you feel pain.",
            })
        days.append({
            "day_label": f"Day {day_number + 1} - {label}",
            "focus": ", ".join(candidates[0].get("muscle_groups", [])) or "Full body",
            "exercises": exercises,
        })
    return WeeklyWorkoutPlan(
        days=days,
        weekly_summary="A balanced weekly plan generated from the available reference exercises.",
    )


async def generate_workout_plan(
    db, req: WorkoutPlanRequest, source: str = "generate_button",
) -> WorkoutPlanResponse:
    if not req.user_id:
        raise ValueError("Authenticated user id is required to generate a workout plan")

    profile = await get_user_profile(db, req.user_id)
    experience = req.experience_override or FitnessExperience(profile["fitness_experience"])
    goal = req.goal_override or FitnessGoal(profile["fitness_goal"])

    day_labels = SPLIT_TEMPLATES.get(req.days_per_week, SPLIT_TEMPLATES[3])

    candidates = await get_candidate_exercises(
        db, req.location, experience, req.excluded_muscle_groups,
    )
    candidate_ids = {c["id"] for c in candidates}
    candidates_text = format_exercise_candidates_for_prompt(candidates)

    try:
        raw_plan: WeeklyWorkoutPlan = await asyncio.to_thread(
            generate_structured,
            SYSTEM_PROMPT,
            _build_user_prompt(goal, experience, req, day_labels, candidates_text),
            WeeklyWorkoutPlan,
        )
    except Exception as exc:
        logger.warning("Structured workout planning failed; using deterministic exercise fallback: %s", exc)
        raw_plan = _fallback_plan(candidates, day_labels)

    validated_plan = _validate_plan(raw_plan, candidate_ids)
    
    # Ensure ALL scheduled days have at least one valid exercise.
    # If any single day is wiped out due to hallucinations, abandon the corrupted plan entirely.
    if not all(day.exercises for day in validated_plan.days):
        logger.warning("Structured workout plan contained empty days after validation; using fallback.")
        validated_plan = _fallback_plan(candidates, day_labels)

    response = WorkoutPlanResponse(
        user_id=req.user_id,
        plan=validated_plan,
        generated_at=datetime.now(timezone.utc).isoformat(),
        source=source,
    )

    await db.workout_plans.update_one(
        {"user_id": req.user_id},
        {"$set": response.model_dump()},
        upsert=True,
    )
    return response
