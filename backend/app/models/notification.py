"""
Notification models and schemas
"""
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class NotificationType(str, Enum):
    """Supported reminder and notification categories."""
    WORKOUT_REMINDER = "workout_reminder"
    MEAL_REMINDER = "meal_reminder"
    WATER_INTAKE_REMINDER = "water_intake_reminder"
    MOTIVATION = "motivation"
    WEEKLY_PROGRESS_REMINDER = "weekly_progress_reminder"


class NotificationPriority(str, Enum):
    """Push priority for reminders."""
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"


class NotificationChannel(str, Enum):
    """Delivery channel for the notification."""
    IN_APP = "in_app"
    PUSH = "push"
    EMAIL = "email"


class NotificationCreate(BaseModel):
    """Schema for creating a notification."""
    type: NotificationType
    title: str = Field(..., min_length=1, max_length=120)
    message: str = Field(..., min_length=1, max_length=500)
    scheduled_for: Optional[datetime] = None
    channel: NotificationChannel = NotificationChannel.IN_APP
    priority: NotificationPriority = NotificationPriority.NORMAL


class NotificationResponse(BaseModel):
    """Response model for a notification record."""
    id: str
    user_id: str
    type: NotificationType
    title: str
    message: str
    channel: NotificationChannel
    priority: NotificationPriority
    status: str
    is_read: bool = False
    scheduled_for: Optional[datetime] = None
    sent_at: Optional[datetime] = None
    read_at: Optional[datetime] = None
    created_at: datetime


class NotificationReadUpdate(BaseModel):
    """Schema for marking a notification as read."""
    is_read: bool = True
