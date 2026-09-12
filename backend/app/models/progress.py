# backend/app/models/progress.py
"""
Progress tracking models
"""
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional
from datetime import date, datetime


class ProgressCreate(BaseModel):
    """Schema for creating a daily progress entry."""
    date: date
    weight: Optional[float] = Field(None, gt=0, description="Weight in kg")
    workout_completed: bool = False
    calories_consumed: Optional[int] = Field(None, ge=0)
    calories_burned: Optional[int] = Field(None, ge=0)
    water_intake: Optional[float] = Field(None, ge=0, description="Water in liters")
    sleep_hours: Optional[float] = Field(None, ge=0, le=24)
    steps: Optional[int] = Field(None, ge=0, description="Daily step count")
    active_minutes: Optional[int] = Field(None, ge=0, description="Minutes of activity")
    goal_completion: Optional[float] = Field(None, ge=0, le=100, description="Progress toward goal in percent")
    notes: Optional[str] = Field(None, max_length=500)

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "date": "2026-08-12",
                "weight": 72.5,
                "workout_completed": True,
                "calories_consumed": 2200,
                "calories_burned": 420,
                "water_intake": 2.5,
                "sleep_hours": 7.5,
                "steps": 8500,
                "active_minutes": 45,
                "goal_completion": 78.5,
                "notes": "Felt great during workout!"
            }
        }
    )


class ProgressResponse(BaseModel):
    """Response model for progress data."""
    id: str
    user_id: str
    date: date
    weight: Optional[float]
    workout_completed: bool
    calories_consumed: Optional[int]
    calories_burned: Optional[int]
    water_intake: Optional[float]
    sleep_hours: Optional[float]
    steps: Optional[int]
    active_minutes: Optional[int]
    goal_completion: Optional[float]
    notes: Optional[str]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ProgressStats(BaseModel):
    """Statistics for user progress."""
    total_workouts: int
    total_days_tracked: int
    avg_weight: Optional[float]
    weight_change: Optional[float]
    workout_streak: int
    avg_calories: Optional[float]
    avg_calories_burned: Optional[float]
    avg_water_intake: Optional[float]
    avg_sleep_hours: Optional[float]
    avg_steps: Optional[float]
    avg_active_minutes: Optional[float]
    goal_completion_rate: Optional[float]

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "total_workouts": 15,
                "total_days_tracked": 20,
                "avg_weight": 71.2,
                "weight_change": -1.8,
                "workout_streak": 5,
                "avg_calories": 2150,
                "avg_calories_burned": 420,
                "avg_water_intake": 2.3,
                "avg_sleep_hours": 7.2,
                "avg_steps": 8400,
                "avg_active_minutes": 48,
                "goal_completion_rate": 76.5
            }
        }
    )


class ProgressUpdate(BaseModel):
    """Schema for updating progress entry."""
    weight: Optional[float] = Field(None, gt=0, description="Weight in kg")
    workout_completed: Optional[bool] = None
    calories_consumed: Optional[int] = Field(None, ge=0)
    calories_burned: Optional[int] = Field(None, ge=0)
    water_intake: Optional[float] = Field(None, ge=0)
    sleep_hours: Optional[float] = Field(None, ge=0, le=24)
    steps: Optional[int] = Field(None, ge=0)
    active_minutes: Optional[int] = Field(None, ge=0)
    goal_completion: Optional[float] = Field(None, ge=0, le=100)
    notes: Optional[str] = Field(None, max_length=500)