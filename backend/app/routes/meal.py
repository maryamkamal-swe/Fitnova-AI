from datetime import date, datetime

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field
from bson.errors import InvalidId

from app.database import get_database
from app.models.meal import MealPlanRequest, MealPlanResponse
from app.services.meal_planner_service import generate_weekly_meal_plan
from app.services.calorie_service import calculate_food_nutrition
from app.services.food_filter_service import DEFAULT_STAPLE_FOODS
from app.services.progress_service import ProgressService
from app.utils.security import get_current_user_id
from app.core.limiter import limiter

router = APIRouter(prefix="/meal-plans", tags=["Meal Planner"])
date_type = date


class FoodLogRequest(BaseModel):
    food_name: str = Field(..., min_length=1, max_length=200)
    food_id: str | None = Field(default=None, min_length=1, max_length=200)
    calories: float | None = Field(default=None, ge=0, le=100_000)
    meal_type: str = Field(default="snack", min_length=1, max_length=50)
    protein_g: float | None = Field(default=None, ge=0, le=10_000)
    carbs_g: float | None = Field(default=None, ge=0, le=10_000)
    fat_g: float | None = Field(default=None, ge=0, le=10_000)
    serving_grams: float = Field(default=100, gt=0, le=100_000)
    serving_size_grams: float | None = Field(default=None, gt=0, le=100_000)
    servings: float = Field(default=1, gt=0, le=100)
    date: date_type = Field(default_factory=date.today)


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
    database = get_database()
    reference = None
    if food_data.food_id:
        reference = await database.foods_ref.find_one({"id": food_data.food_id})
        if reference is None:
            reference = next(
                (food for food in DEFAULT_STAPLE_FOODS if food["id"] == food_data.food_id),
                None,
            )
    if reference is None:
        reference = await database.foods_ref.find_one(
            {"name": {"$regex": f"^{food_data.food_name}$", "$options": "i"}}
        )
    if reference is None:
        reference = next(
            (
                food for food in DEFAULT_STAPLE_FOODS
                if food["name"].lower() == food_data.food_name.lower()
            ),
            None,
        )

    serving_grams = food_data.serving_size_grams or food_data.serving_grams
    if reference is not None:
        nutrition = calculate_food_nutrition(
            reference, serving_grams, food_data.servings
        )
        canonical_name = reference.get("name", food_data.food_name)
        canonical_id = str(reference.get("id") or food_data.food_id or canonical_name)
    elif food_data.calories is not None:
        # Compatibility for free-form foods that are not in the reference set.
        nutrition = {
            "calories": round(food_data.calories, 2),
            "protein_g": food_data.protein_g,
            "carbs_g": food_data.carbs_g,
            "fat_g": food_data.fat_g,
            "serving_grams": round(serving_grams * food_data.servings, 2),
        }
        canonical_name = food_data.food_name.strip()
        canonical_id = food_data.food_id or canonical_name.lower().replace(" ", "-")
    else:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Food must include a reference food or calories",
        )

    collection = database.food_logs
    now = datetime.utcnow()
    food_doc = {
        "user_id": user_id,
        "food_id": canonical_id,
        "food_name": canonical_name,
        **nutrition,
        "meal_type": food_data.meal_type,
        "date": datetime.combine(food_data.date, datetime.min.time()),
        "created_at": now,
    }
    result = await collection.insert_one(food_doc)
    progress = await ProgressService().increment_progress(
        user_id, food_data.date, calories_consumed=round(nutrition["calories"])
    )
    food_doc["id"] = str(result.inserted_id)
    food_doc.pop("_id", None)
    logged_foods = await collection.find(
        {
            "user_id": user_id,
            "date": datetime.combine(food_data.date, datetime.min.time()),
        }
    ).sort("created_at", 1).to_list(length=200)
    foods_response = []
    for item in logged_foods:
        item["id"] = str(item.pop("_id"))
        foods_response.append(item)
    return {
        "message": "Food logged successfully",
        "id": str(result.inserted_id),
        "food": food_doc,
        "foods": foods_response,
        "progress": progress.model_dump(mode="json"),
    }


@router.get("/food-log")
async def get_food_log(
    date_value: date_type = Query(default_factory=date.today, alias="date"),
    user_id: str = Depends(get_current_user_id),
):
    """Return canonical food entries for one local calendar date."""
    day = datetime.combine(date_value, datetime.min.time())
    entries = await get_database().food_logs.find(
        {"user_id": user_id, "date": day}
    ).sort("created_at", 1).to_list(length=200)
    for entry in entries:
        entry["id"] = str(entry.pop("_id"))
    return {"date": str(date_value), "foods": entries}




@router.post("/food-log/{food_id}/favorite", status_code=status.HTTP_200_OK)
async def toggle_favorite(
    food_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Add or remove a food item from favorites.
    """
    collection = get_database().food_logs
    try:
        oid = ObjectId(food_id)
    except (InvalidId, TypeError) as error:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Food item not found") from error
    
    result = await collection.update_one(
        {"_id": oid, "user_id": user_id}, 
        {"$set": {"favorite": True, "updated_at": datetime.utcnow()}}
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Food log entry not found")
    return {"message": "Favorite status updated successfully"}

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
@router.get("/me", response_model=MealPlanResponse)
@router.get("/current", response_model=MealPlanResponse)
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
