"""
Notification routes for reminder and engagement flows.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from ..models.notification import (
    NotificationChannel,
    NotificationCreate,
    NotificationPriority,
    NotificationResponse,
    NotificationType,
)
from ..services.notification_service import NotificationService
from ..utils.security import get_current_user_id
from ..core.limiter import limiter

router = APIRouter(prefix="/notifications", tags=["Notifications"])
notification_service = NotificationService()


@router.post("", response_model=NotificationResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/hour")
async def create_notification(
    request: Request,
    notification_data: NotificationCreate,
    user_id: str = Depends(get_current_user_id),
):
    """Create a notification for the authenticated user."""
    return await notification_service.create_notification(user_id, notification_data)


@router.post("/smart", response_model=NotificationResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/hour")
async def create_smart_notification(
    request: Request,
    notification_type: NotificationType,
    title: Optional[str] = None,
    message: Optional[str] = None,
    scheduled_for: Optional[datetime] = None,
    channel: NotificationChannel = NotificationChannel.IN_APP,
    priority: NotificationPriority = NotificationPriority.NORMAL,
    user_id: str = Depends(get_current_user_id),
):
    """Create a reminder using predefined smart notification templates."""
    return await notification_service.create_smart_notification(
        user_id=user_id,
        notification_type=notification_type,
        title=title,
        message=message,
        scheduled_for=scheduled_for,
        channel=channel,
        priority=priority,
    )


@router.get("", response_model=list[NotificationResponse])
@limiter.limit("60/minute")
async def get_notifications(
    request: Request,
    unread_only: bool = Query(False),
    limit: int = Query(20, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
):
    """Fetch the most recent notifications for the authenticated user."""
    return await notification_service.get_notifications(user_id, unread_only, limit)


@router.get("/unread", response_model=list[NotificationResponse])
@limiter.limit("60/minute")
async def get_unread_notifications(
    request: Request,
    user_id: str = Depends(get_current_user_id),
):
    """Get unread notifications for the current user."""
    return await notification_service.get_notifications(user_id, unread_only=True, limit=50)


@router.patch("/{notification_id}/read", response_model=NotificationResponse)
@limiter.limit("60/minute")
async def mark_notification_as_read(
    request: Request,
    notification_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Mark a notification as read."""
    return await notification_service.mark_as_read(notification_id, user_id)


@router.post("/{notification_id}/send", response_model=NotificationResponse)
@limiter.limit("10/hour")
async def send_notification(
    request: Request,
    notification_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Trigger a push send attempt for a stored notification."""
    collection = notification_service._get_collection()
    notification = await collection.find_one({
        "_id": notification_service.parse_notification_id(notification_id),
        "user_id": user_id,
    })
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )

    response = notification_service._format_notification_response(notification)
    push_sent = await notification_service.send_push_notification(user_id, response)
    return response.model_copy(update={"push_sent": push_sent})