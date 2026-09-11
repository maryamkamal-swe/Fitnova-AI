"""
Meal planner models and schemas
"""
from pydantic import BaseModel, Field
from typing import List, Optional


class FoodRef(BaseModel):
    """A single document from the foods_ref reference collection."""
    id: str
    name: str
    cuisine: str  # e.g. "desi"
    category: str  # "breakfast" | "lunch" | "dinner" | "snack"
    calories_per_100g: float
    protein_g_per_100g: float
    carbs_g_per_100g: float
    fat_g_per_100g: float
    tags: List[str] = Field(default_factory=list)  # e.g. ["vegetarian", "high_protein"]


class PlannedMealItem(BaseModel):
    """One dish as chosen by the LLM, before the backend rescales its portion."""
    food_id: str = Field(description="Must be one of the candidate food_id values provided")
    food_name: str
    portion_grams: float = Field(description="Rough starting portion; backend rescales precisely")
    calories: Optional[float] = Field(default=None, description="Computed by backend after rescaling, not by the LLM")


class DayMealPlan(BaseModel):
    day_label: str  # "Monday"
    breakfast: List[PlannedMealItem]
    lunch: List[PlannedMealItem]
    dinner: List[PlannedMealItem]
    snacks: List[PlannedMealItem]
    note: Optional[str] = Field(default=None, description="One short encouraging line for the day")


class WeeklyMealPlan(BaseModel):
    """The exact JSON shape we ask the LLM to return."""
    days: List[DayMealPlan]
    weekly_summary: str = Field(description="2-3 sentence overview of the week's nutrition focus")


class MealPlanRequest(BaseModel):
    """
    goal, weight, height, age, gender, activity_level and dietary_preferences
    are all read from the user's saved profile -- only cuisine is separate
    since it isn't currently a profile field.
    """
    user_id: Optional[str] = None
    cuisine: str = "desi"


class MealPlanResponse(BaseModel):
    user_id: str
    daily_calorie_target: float
    meal_calorie_split: dict
    plan: WeeklyMealPlan
    generated_at: str
    source: str  # "generate_button" | "weekly_auto_update"
