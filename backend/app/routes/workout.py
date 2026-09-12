from fastapi import APIRouter, Depends, HTTPException, Request

from app.database import get_database
from app.models.workout import WorkoutPlanRequest, WorkoutPlanResponse
from app.services.workout_planner_service import generate_workout_plan
from app.utils.security import get_current_user_id
from app.core.limiter import limiter

router = APIRouter(prefix="/workout-plans", tags=["Workout Planner"])


@router.post("/generate", response_model=WorkoutPlanResponse)
@limiter.limit("10/minute")
async def generate(
    request: Request,
    req: WorkoutPlanRequest,
    db=Depends(get_database),
    authenticated_user_id: str = Depends(get_current_user_id),
):
    """
    Triggered by the 'Generate plan' button on the dashboard.
    No chat, no NLU -- structured input in, structured plan out.
    """
    try:
        request_for_user = req.model_copy(update={"user_id": authenticated_user_id})
        return await generate_workout_plan(
            db, request_for_user, source="generate_button"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/{user_id}", response_model=WorkoutPlanResponse, deprecated=True)
@router.get("/me", response_model=WorkoutPlanResponse)
@router.get("/current", response_model=WorkoutPlanResponse)
async def get_current_plan(
    user_id: str | None = None,
    db=Depends(get_database),
    authenticated_user_id: str = Depends(get_current_user_id),
):
    del user_id
    doc = await db.workout_plans.find_one({"user_id": authenticated_user_id})
    if not doc:
        raise HTTPException(status_code=404, detail="No workout plan found for this user yet")
    return doc
