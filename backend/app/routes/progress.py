"""
Progress tracking routes
Handles daily progress logging and statistics
"""
from fastapi import APIRouter, HTTPException, status, Depends, Query
from typing import Optional, List
from datetime import date, timedelta, datetime
from pydantic import BaseModel, Field, model_validator
from ..database import get_database
from ..models.progress import ProgressCreate, ProgressResponse, ProgressStats, ProgressUpdate
from ..services.progress_service import ProgressService
from ..utils.security import get_current_user_id
from ..utils.validators import validate_date_range, validate_pagination

router = APIRouter(prefix="/progress", tags=["Progress Tracking"])
progress_service = ProgressService()
date_type = date


class HydrationLogRequest(BaseModel):
    added_amount: Optional[float] = Field(default=None, gt=0, le=100)
    liters: Optional[float] = Field(default=None, gt=0, le=100)
    date: date_type

    @model_validator(mode="after")
    def require_added_amount(self):
        if self.added_amount is None and self.liters is None:
            raise ValueError("added_amount is required")
        if self.added_amount is not None and self.liters is not None:
            raise ValueError("Provide only added_amount")
        if self.added_amount is None:
            self.added_amount = self.liters
        return self


@router.post("", response_model=ProgressResponse, status_code=status.HTTP_201_CREATED)
async def log_progress(
    progress_data: ProgressCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Log daily progress
    
    - **date**: Progress date
    - **weight**: Current weight (optional)
    - **workout_completed**: Whether workout was completed
    - **calories_consumed**: Daily calorie intake (optional)
    - **water_intake**: Water consumed in liters (optional)
    - **sleep_hours**: Hours slept (optional)
    - **notes**: Personal notes (optional)
    
    Requires authentication
    """
    return await progress_service.create_progress(user_id, progress_data)


@router.get("/history", response_model=List[ProgressResponse])
async def get_progress_history(
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD)"),
    skip: int = Query(0, ge=0),
    limit: int = Query(30, ge=1, le=100),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get progress history with optional date filtering
    
    - **start_date**: Filter from this date (optional)
    - **end_date**: Filter until this date (optional)
    - **skip**: Number of records to skip (pagination)
    - **limit**: Maximum records to return (max 100)
    
    Requires authentication
    """
    # Validate date range
    start_date, end_date = validate_date_range(start_date, end_date)
    
    # Validate pagination
    skip, limit = validate_pagination(skip, limit)
    
    return await progress_service.get_progress_history(
        user_id,
        start_date,
        end_date,
        skip,
        limit
    )


@router.get("/stats", response_model=ProgressStats)
async def get_progress_stats(
    days: int = Query(30, ge=1, le=365, description="Number of days to analyze"),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get progress statistics
    
    - **days**: Number of days to analyze (default 30, max 365)
    
    Returns aggregated statistics including:
    - Total workouts completed
    - Average weight
    - Weight change
    - Workout streak
    - Average calories/water/sleep
    
    Requires authentication
    """
    return await progress_service.get_progress_stats(user_id, days)


@router.get("/today", response_model=ProgressResponse)
async def get_today_progress(user_id: str = Depends(get_current_user_id)):
    """
    Get today's progress entry
    
    Returns today's progress or 404 if not logged yet
    
    Requires authentication
    """
    today = date.today()
    progress = await progress_service.get_progress_by_date(user_id, today)
    
    if not progress:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No progress logged for today"
        )
    
    return progress


@router.get("/hydration/today")
async def get_today_hydration(
    date_value: date_type = Query(..., alias="date"),
    user_id: str = Depends(get_current_user_id),
):
    """
    Get today's hydration entry.

    Requires authentication.
    """
    collection = get_database().progress
    day_start = datetime.combine(date_value, datetime.min.time())
    day_end = day_start + timedelta(days=1)
    
    entry = await collection.find_one({
        "user_id": user_id,
        "date": {"$gte": day_start, "$lt": day_end},
    })
    if not entry:
        entry = await collection.find_one({"user_id": user_id, "date": day_start})
    if not entry:
        return {"liters": 0, "date": str(date_value)}
    return {"liters": entry.get("water_intake", 0), "date": str(date_value)}


@router.get("/{progress_id}", response_model=ProgressResponse)
async def get_progress_by_id(
    progress_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get specific progress entry by ID
    
    Requires authentication
    """
    progress = await progress_service.get_progress_by_id(progress_id, user_id)
    
    if not progress:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Progress entry not found"
        )
    
    return progress


@router.put("/{progress_id}", response_model=ProgressResponse)
async def update_progress(
    progress_id: str,
    progress_data: ProgressUpdate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update existing progress entry
    
    Only updates provided fields (partial update)
    
    Requires authentication
    """
    return await progress_service.update_progress(progress_id, user_id, progress_data)


@router.delete("/{progress_id}", status_code=status.HTTP_200_OK)
async def delete_progress(
    progress_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Delete progress entry
    
    Requires authentication
    """
    await progress_service.delete_progress(progress_id, user_id)
    return {"message": "Progress entry deleted successfully"}


@router.post("/hydration")
async def log_hydration(
    hydration_data: HydrationLogRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Log water intake for the day.

    - **liters**: Water consumed in liters
    - **date**: Date of hydration entry (optional, defaults to today)

    Requires authentication.
    """
    collection = get_database().progress
    entry_datetime = datetime.combine(hydration_data.date, datetime.min.time())

    result = await collection.update_one(
        {"user_id": user_id, "date": entry_datetime},
        {
            "$inc": {"water_intake": hydration_data.added_amount},
            "$set": {"updated_at": datetime.utcnow()},
            "$setOnInsert": {"created_at": datetime.utcnow(), "workout_completed": False},
        },
        upsert=True,
    )
    entry = await collection.find_one({"user_id": user_id, "date": entry_datetime})
    return {
        "message": "Hydration logged successfully",
        "liters": entry.get("water_intake", 0) if entry else 0,
        "date": str(hydration_data.date),
    }


@router.get("/chart/weight")
async def get_weight_chart_data(
    days: int = Query(30, ge=7, le=365),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get weight data for charting
    
    - **days**: Number of days to include (7-365)
    
    Returns date and weight pairs for visualization
    
    Requires authentication
    """
    start_date = date.today() - timedelta(days=days)
    history = await progress_service.get_progress_history(
        user_id,
        start_date,
        date.today(),
        0,
        days
    )
    
    # Extract weight data
    weight_data = [
        {
            "date": str(entry.date),
            "weight": entry.weight
        }
        for entry in history if entry.weight is not None
    ]
    
    return {
        "data": weight_data,
        "period_days": days
    }


@router.get("/chart/calories")
async def get_calories_chart_data(
    days: int = Query(30, ge=7, le=365),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get calorie intake data for charting
    
    - **days**: Number of days to include (7-365)
    
    Returns date and calories pairs for visualization
    
    Requires authentication
    """
    start_date = date.today() - timedelta(days=days)
    history = await progress_service.get_progress_history(
        user_id,
        start_date,
        date.today(),
        0,
        days
    )
    
    # Extract calorie data
    calorie_data = [
        {
            "date": str(entry.date),
            "calories": entry.calories_consumed
        }
        for entry in history if entry.calories_consumed is not None
    ]
    
    return {
        "data": calorie_data,
        "period_days": days
    }