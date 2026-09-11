"""
Notification service for reminder and engagement messages.
"""
import logging
from datetime import datetime
from typing import Optional, List

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException, status

from ..database import get_database
from ..models.notification import (
    NotificationChannel,
    NotificationCreate,
    NotificationPriority,
    NotificationResponse,
    NotificationType,
)

logger = logging.getLogger(__name__)


class NotificationService:
    def __init__(self):
        self.db = None
        self.notifications_collection = None

    def _get_collection(self):
        """Lazy-load the notifications collection."""
        if self.notifications_collection is None:
            self.db = get_database()
            self.notifications_collection = self.db.notifications
        return self.notifications_collection

    @staticmethod
    def parse_notification_id(notification_id: str) -> ObjectId:
        """Convert a public notification identifier into a safe MongoDB ObjectId."""
        try:
            return ObjectId(notification_id)
        except (InvalidId, TypeError) as error:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notification not found",
            ) from error

    @staticmethod
    def default_template(notification_type: NotificationType) -> dict:
        """Return a default smart reminder message template."""
        templates = {
            NotificationType.WORKOUT_REMINDER: {
                "title": "Workout reminder",
                "message": "Time to move! Complete your planned workout to stay consistent.",
            },
            NotificationType.MEAL_REMINDER: {
                "title": "Meal reminder",
                "message": "Don’t forget your next meal. Fuel your body with balanced nutrition.",
            },
            NotificationType.WATER_INTAKE_REMINDER: {
                "title": "Hydration reminder",
                "message": "Take a glass of water now to stay hydrated and energized.",
            },
            NotificationType.MOTIVATION: {
                "title": "You’ve got this",
                "message": "Small consistent steps lead to big fitness results. Keep going!",
            },
            NotificationType.WEEKLY_PROGRESS_REMINDER: {
                "title": "Weekly check-in",
                "message": "Review your progress this week and keep your momentum going.",
            },
        }

        return templates.get(notification_type, {
            "title": "FitNova reminder",
            "message": "A quick reminder from your FitNova coach.",
        })

    async def create_notification(
        self,
        user_id: str,
        notification_data: NotificationCreate,
    ) -> NotificationResponse:
        """Create a notification record for a user."""
        collection = self._get_collection()

        now = datetime.utcnow()
        schedule_time = notification_data.scheduled_for or now
        status = "scheduled" if notification_data.scheduled_for else "sent"

        notification_doc = {
            "user_id": user_id,
            "type": notification_data.type.value,
            "title": notification_data.title,
            "message": notification_data.message,
            "channel": notification_data.channel.value,
            "priority": notification_data.priority.value,
            "status": status,
            "is_read": False,
            "scheduled_for": schedule_time,
            "sent_at": None if notification_data.scheduled_for else now,
            "read_at": None,
            "created_at": now,
        }

        result = await collection.insert_one(notification_doc)
        created = await collection.find_one({"_id": result.inserted_id})
        return self._format_notification_response(created)

    async def create_smart_notification(
        self,
        user_id: str,
        notification_type: NotificationType,
        title: Optional[str] = None,
        message: Optional[str] = None,
        scheduled_for: Optional[datetime] = None,
        channel: NotificationChannel = NotificationChannel.IN_APP,
        priority: NotificationPriority = NotificationPriority.NORMAL,
    ) -> NotificationResponse:
        """Create a notification from a smart template."""
        template = self.default_template(notification_type)
        payload = NotificationCreate(
            type=notification_type,
            title=title or template["title"],
            message=message or template["message"],
            scheduled_for=scheduled_for,
            channel=channel,
            priority=priority,
        )
        return await self.create_notification(user_id, payload)

    async def get_notifications(
        self,
        user_id: str,
        unread_only: bool = False,
        limit: int = 20,
    ) -> List[NotificationResponse]:
        """Get notifications for a user."""
        collection = self._get_collection()
        query = {"user_id": user_id}
        if unread_only:
            query["is_read"] = False

        cursor = collection.find(query).sort("created_at", -1).limit(limit)
        notifications = await cursor.to_list(length=limit)
        return [self._format_notification_response(item) for item in notifications]

    async def mark_as_read(self, notification_id: str, user_id: str) -> NotificationResponse:
        """Mark a notification as read."""
        collection = self._get_collection()
        notification_object_id = self.parse_notification_id(notification_id)
        notification = await collection.find_one({
            "_id": notification_object_id,
            "user_id": user_id,
        })

        if not notification:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notification not found",
            )

        await collection.update_one(
            {"_id": notification_object_id},
            {"$set": {"is_read": True, "read_at": datetime.utcnow()}} 
        )

        updated = await collection.find_one({"_id": notification_object_id})
        return self._format_notification_response(updated)

    async def send_push_notification(self, user_id: str, notification: NotificationResponse) -> bool:
        """Send a push notification when Firebase is configured.

        If Firebase is not configured, the notification is still stored for in-app delivery.
        """
        if notification.channel != NotificationChannel.PUSH:
            return True

        try:
            import firebase_admin
            from firebase_admin import messaging
        except ImportError:
            logger.warning(
                "Firebase admin SDK is not installed. Notification stored only. "
                "Install firebase-admin to enable push delivery."
            )
            return False

        if not firebase_admin._apps:
            logger.warning("Firebase app is not initialized. Push notifications are disabled.")
            return False

        try:
            message = messaging.Message(
                notification={
                    "title": notification.title,
                    "body": notification.message,
                },
                data={
                    "type": notification.type.value,
                    "notification_id": notification.id,
                },
            )
            messaging.send(message)
            return True
        except Exception as exc:
            logger.exception("Failed to send push notification: %s", exc)
            return False

    def _format_notification_response(self, notification_doc: dict) -> NotificationResponse:
        """Convert MongoDB document into a NotificationResponse."""
        return NotificationResponse(
            id=str(notification_doc["_id"]),
            user_id=str(notification_doc["user_id"]),
            type=NotificationType(notification_doc["type"]),
            title=notification_doc["title"],
            message=notification_doc["message"],
            channel=NotificationChannel(notification_doc["channel"]),
            priority=NotificationPriority(notification_doc["priority"]),
            status=notification_doc["status"],
            is_read=notification_doc.get("is_read", False),
            scheduled_for=notification_doc.get("scheduled_for"),
            sent_at=notification_doc.get("sent_at"),
            read_at=notification_doc.get("read_at"),
            created_at=notification_doc["created_at"],
        )
