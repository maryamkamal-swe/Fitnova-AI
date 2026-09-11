"""
Workout planner models and schemas
"""
from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum

from .user import FitnessGoal, FitnessExperience


class WorkoutLocation(str, Enum):
    HOME = "home"
    GYM = "gym"


class ExerciseRef(BaseModel):
    """A single document from the exercises_ref reference collection."""
    id: str
    name: str
    muscle_groups: List[str]
    equipment: WorkoutLocation
    difficulty: FitnessExperience
    exercise_type: str  # "compound" | "isolation" | "cardio"


class PlannedExercise(BaseModel):
    """One exercise as chosen by the LLM for a given day."""
    exercise_id: str = Field(description="Must be one of the candidate exercise_id values provided")
    exercise_name: str
    sets: int
    reps: str = Field(description="e.g. '8-12' for strength work, or '30s' for a timed hold/cardio")
    rest_seconds: int
    coaching_note: Optional[str] = Field(
        default=None, description="One short, encouraging line of form/coaching advice"
    )


class WorkoutDay(BaseModel):
    day_label: str = Field(description="e.g. 'Day 1 - Push'")
    focus: str = Field(description="e.g. 'Chest, shoulders, triceps'")
    exercises: List[PlannedExercise]


class WeeklyWorkoutPlan(BaseModel):
    """The exact JSON shape we ask the LLM to return."""
    days: List[WorkoutDay]
    weekly_summary: str = Field(description="2-3 sentence overview of the week's training focus")


class WorkoutPlanRequest(BaseModel):
    """
    Only fields NOT already stored on the user's profile go here.
    Goal and experience are read from profile.fitness_goal / profile.fitness_experience,
    but can optionally be overridden per-request if the frontend lets a user tweak them.
    """
    user_id: Optional[str] = None
    location: WorkoutLocation
    days_per_week: int = Field(ge=1, le=6, default=3)
    excluded_muscle_groups: List[str] = Field(default_factory=list)
    experience_override: Optional[FitnessExperience] = None
    goal_override: Optional[FitnessGoal] = None


class WorkoutPlanResponse(BaseModel):
    user_id: str
    plan: WeeklyWorkoutPlan
    generated_at: str
    source: str  # "generate_button" | "weekly_auto_update"
