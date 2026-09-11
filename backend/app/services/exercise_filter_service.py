from app.models.user import FitnessExperience
from app.models.workout import WorkoutLocation

# A user at a given experience level can also draw from easier tiers,
# so a plan doesn't feel artificially restricted.
EXPERIENCE_LADDER = {
    FitnessExperience.BEGINNER: [FitnessExperience.BEGINNER],
    FitnessExperience.INTERMEDIATE: [FitnessExperience.BEGINNER, FitnessExperience.INTERMEDIATE],
    FitnessExperience.ADVANCED: [
        FitnessExperience.BEGINNER, FitnessExperience.INTERMEDIATE, FitnessExperience.ADVANCED,
    ],
}


DEFAULT_EXERCISES = [
    {"id": "ex-pushups", "name": "Push-ups", "muscle_groups": ["chest", "triceps", "shoulders"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "home"},
    {"id": "ex-squats", "name": "Squats", "muscle_groups": ["quads", "glutes"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "home"},
    {"id": "ex-dumbbell-press", "name": "Dumbbell Press", "muscle_groups": ["chest", "shoulders"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "gym"},
    {"id": "ex-plank", "name": "Plank", "muscle_groups": ["core"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "home"},
    {"id": "ex-rows", "name": "Dumbbell Rows", "muscle_groups": ["back", "biceps"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "gym"},
    {"id": "ex-lunges", "name": "Lunges", "muscle_groups": ["quads", "glutes"], "exercise_type": "strength", "difficulty": "beginner", "equipment": "home"},
]


def _default_exercises(location: WorkoutLocation, excluded_muscle_groups: list[str]) -> list[dict]:
    excluded = {group.lower() for group in excluded_muscle_groups}
    matches = []
    for exercise in DEFAULT_EXERCISES:
        if excluded and any(group in excluded for group in exercise["muscle_groups"]):
            continue
        matches.append(exercise)
    if location == WorkoutLocation.HOME:
        home = [item for item in matches if item["equipment"] == "home"]
        if home:
            return home
    return matches or list(DEFAULT_EXERCISES)


async def get_candidate_exercises(
    db, location: WorkoutLocation, experience: FitnessExperience,
    excluded_muscle_groups: list[str], limit: int = 80,
) -> list[dict]:
    query: dict = {
        "equipment": location.value,
        "difficulty": {"$in": [lvl.value for lvl in EXPERIENCE_LADDER[experience]]},
    }
    if excluded_muscle_groups:
        query["muscle_groups"] = {"$nin": excluded_muscle_groups}

    cursor = db.exercises_ref.find(query).limit(limit)
    exercises = [doc async for doc in cursor]
    if exercises:
        return exercises
    return _default_exercises(location, excluded_muscle_groups)[:limit]


def format_exercise_candidates_for_prompt(exercises: list[dict]) -> str:
    """Turns raw Mongo docs into a compact, LLM-readable candidate list."""
    lines = []
    for ex in exercises:
        lines.append(
            f"- id={ex['id']} | {ex['name']} | muscles={','.join(ex['muscle_groups'])} "
            f"| type={ex['exercise_type']} | difficulty={ex['difficulty']}"
        )
    return "\n".join(lines)
