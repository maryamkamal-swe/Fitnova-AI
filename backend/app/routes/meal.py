from datetime import date, datetime

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field

from app.database import get_database
from app.models.meal import MealPlanRequest, MealPlanResponse
from app.services.meal_planner_service import generate_weekly_meal_plan
from app.utils.security import get_current_user_id
from app.core.limiter import limiter

router = APIRouter(prefix="/meal-plans", tags=["Meal Planner"])
date_type = date


class FoodLogRequest(BaseModel):
    food_name: str = Field(..., min_length=1, max_length=200)
    calories: float = Field(..., ge=0, le=100_000)
    meal_type: str = Field(default="snack", min_length=1, max_length=50)
    protein_g: float | None = Field(default=None, ge=0, le=10_000)
    carbs_g: float | None = Field(default=None, ge=0, le=10_000)
    fat_g: float | None = Field(default=None, ge=0, le=10_000)
    date: date_type | None = None


class RecipePreparationRequest(BaseModel):
    recipe_id: str = Field(..., min_length=1, max_length=200)
    steps_completed: list[int] = Field(default_factory=list)
    time_spent_minutes: int = Field(default=0, ge=0, le=10_080)


@router.post("/generate", response_model=MealPlanResponse)
@limiter.limit("10/minute")
async def generate(
    request: Request,
    req: MealPlanRequest,
    db=Depends(get_database),
    authenticated_user_id: str = Depends(get_current_user_id),
):
    """
    Triggered by the 'Generate plan' button on the dashboard.
    Calorie math and food filtering happen in code; the LLM only
    selects dish combinations and ensures variety across the week.
    """
    try:
        request_for_user = req.model_copy(update={"user_id": authenticated_user_id})
        return await generate_weekly_meal_plan(
            db, request_for_user, source="generate_button"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/food-log")
async def log_food_entry(
    food_data: FoodLogRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Log a food/nutrition entry for the day.

    - **food_name**: Name of the food item
    - **calories**: Calories consumed
    - **meal_type**: Type of meal (breakfast/lunch/dinner/snack)
    - **protein_g**: Protein in grams (optional)
    - **carbs_g**: Carbs in grams (optional)
    - **fat_g**: Fat in grams (optional)

    Requires authentication.
    """
    collection = get_database().food_logs
    food_doc = {
        "user_id": user_id,
        "food_name": food_data.food_name,
        "calories": food_data.calories,
        "meal_type": food_data.meal_type,
        "protein_g": food_data.protein_g,
        "carbs_g": food_data.carbs_g,
        "fat_g": food_data.fat_g,
        "date": datetime.combine(food_data.date, datetime.min.time()) if food_data.date else datetime.utcnow(),
        "created_at": datetime.utcnow(),
    }
    result = await collection.insert_one(food_doc)
    return {"message": "Food logged successfully", "id": str(result.inserted_id)}


@router.post("/food-log/{food_id}/favorite", status_code=status.HTTP_200_OK)
async def toggle_favorite(
    food_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Add or remove a food item from favorites.
    """
    collection = get_database().food_logs
    result = await collection.update_one(
        {"_id": ObjectId(food_id), "user_id": user_id},
        {"$set": {"favorite": True, "updated_at": datetime.utcnow()}},
    )
    return {"message": "Food marked as favorite"}


@router.get("/meal-replacement", response_model=MealPlanResponse)
async def get_meal_replacements(
    user_id: str = Depends(get_current_user_id),
):
    """
    Get available meal replacements (protein shakes, bars, etc.)
    for the authenticated user.
    """
    collection = get_database().meal_plans
    doc = await collection.find_one({"user_id": user_id})
    if not doc:
        raise HTTPException(status_code=404, detail="No meal plan found")
    replacements = doc.get("meal_replacements", [])
    plan = doc.get("plan")
    if not isinstance(plan, dict) or not isinstance(plan.get("days"), list) or not plan["days"]:
        raise HTTPException(status_code=422, detail="Stored meal plan is incomplete")

    first_day = plan["days"][0]
    snacks = first_day.setdefault("snacks", [])
    for replacement in replacements:
        if not isinstance(replacement, dict):
            continue
        snacks.append(
            {
                "food_id": str(
                    replacement.get("food_id")
                    or replacement.get("id")
                    or replacement.get("food_name")
                    or "meal-replacement"
                ),
                "food_name": str(
                    replacement.get("food_name")
                    or replacement.get("name")
                    or "Meal replacement"
                ),
                "portion_grams": float(
                    replacement.get("portion_grams")
                    or replacement.get("serving_size_grams")
                    or 1
                ),
                "calories": replacement.get("calories"),
            }
        )

    doc["plan"] = plan
    doc.pop("meal_replacements", None)
    return MealPlanResponse.model_validate(doc)


@router.post("/recipe-preparation", response_model=dict)
async def log_recipe_preparation(
    prep_data: RecipePreparationRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Track recipe preparation state (steps completed, time spent).

    - **recipe_id**: ID of the recipe being prepared
    - **steps_completed**: List of completed step indices
    - **time_spent_minutes**: Minutes spent preparing
    """
    collection = get_database().meal_plans
    await collection.update_one(
        {"user_id": user_id},
        {"$set": {
            "preparation_state": {
                "recipe_id": prep_data.recipe_id,
                "steps_completed": prep_data.steps_completed,
                "time_spent_minutes": prep_data.time_spent_minutes,
                "status": "prepared",
                "completed_at": datetime.utcnow(),
            }
        }},
    )
    return {"message": "Recipe preparation state saved", "status": "success"}


@router.get("/{user_id}", response_model=MealPlanResponse, deprecated=True)
@router.get("/current", response_model=MealPlanResponse)
@router.get("/me", response_model=MealPlanResponse)
async def get_current_plan(
    user_id: str | None = None,
    db=Depends(get_database),
    authenticated_user_id: str = Depends(get_current_user_id),
):
    del user_id
    doc = await db.meal_plans.find_one({"user_id": authenticated_user_id})
    if not doc:
        raise HTTPException(status_code=404, detail="No meal plan found for this user yet")
    return doc
