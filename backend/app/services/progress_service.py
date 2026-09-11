"""
Progress tracking service
Handles progress data and statistics
"""
from datetime import datetime, date, time, timedelta
from typing import Optional, List
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException, status
from ..database import get_database
from ..models.progress import ProgressCreate, ProgressResponse, ProgressStats, ProgressUpdate


class ProgressService:
    def __init__(self):
        self.db = None
        self.progress_collection = None

    def _get_collection(self):
        """Lazy load database collection."""
        if self.progress_collection is None:
            self.db = get_database()
            self.progress_collection = self.db.progress
        return self.progress_collection

    @staticmethod
    def _mongo_datetime(value):
        if isinstance(value, datetime):
            return value
        if isinstance(value, date):
            return datetime.combine(value, time.min)
        return value

    @staticmethod
    def calculate_activity_summary(progress_records: List[dict]) -> dict:
        """Aggregate daily activity metrics across a list of records."""
        if not progress_records:
            return {
                "avg_steps": 0,
                "avg_active_minutes": 0,
                "goal_completion_rate": 0,
                "workout_days": 0,
            }

        steps = [item.get("steps") for item in progress_records if item.get("steps") is not None]
        active_minutes = [item.get("active_minutes") for item in progress_records if item.get("active_minutes") is not None]
        goal_completion_values = [item.get("goal_completion") for item in progress_records if item.get("goal_completion") is not None]
        workout_days = sum(1 for item in progress_records if item.get("workout_completed") is True)

        return {
            "avg_steps": round(sum(steps) / len(steps), 2) if steps else 0,
            "avg_active_minutes": round(sum(active_minutes) / len(active_minutes), 2) if active_minutes else 0,
            "goal_completion_rate": round(sum(goal_completion_values) / len(goal_completion_values), 2) if goal_completion_values else 0,
            "workout_days": workout_days,
        }

    async def create_progress(self, user_id: str, progress_data: ProgressCreate) -> ProgressResponse:
        """
        Create or update progress entry for a specific date.
        """
        collection = self._get_collection()

        existing = await collection.find_one({
            "user_id": user_id,
            "date": self._mongo_datetime(progress_data.date)
        })

        if existing:
            update_data = progress_data.dict(exclude_unset=True)
            await collection.update_one(
                {"_id": existing["_id"]},
                {"$set": update_data}
            )

            updated = await collection.find_one({"_id": existing["_id"]})
            return self._format_progress_response(updated)

        progress_doc = {
            "user_id": user_id,
            **progress_data.dict(),
            "created_at": datetime.utcnow()
        }
        progress_doc["date"] = self._mongo_datetime(progress_doc["date"])

        result = await collection.insert_one(progress_doc)
        created = await collection.find_one({"_id": result.inserted_id})
        return self._format_progress_response(created)

    async def get_progress_history(
        self,
        user_id: str,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        skip: int = 0,
        limit: int = 30
    ) -> List[ProgressResponse]:
        """Get progress history with optional date filtering."""
        collection = self._get_collection()
        query = {"user_id": user_id}

        if start_date or end_date:
            query["date"] = {}
            if start_date:
                query["date"]["$gte"] = self._mongo_datetime(start_date)
            if end_date:
                query["date"]["$lte"] = self._mongo_datetime(end_date)

        cursor = collection.find(query).sort("date", -1).skip(skip).limit(limit)
        progress_list = await cursor.to_list(length=limit)
        return [self._format_progress_response(p) for p in progress_list]

    async def get_progress_by_date(self, user_id: str, target_date: date) -> Optional[ProgressResponse]:
        """Get progress entry for specific date."""
        collection = self._get_collection()
        progress = await collection.find_one({
            "user_id": user_id,
            "date": self._mongo_datetime(target_date)
        })

        if progress:
            return self._format_progress_response(progress)
        return None

    async def get_progress_by_id(self, progress_id: str, user_id: str) -> Optional[ProgressResponse]:
        """Get progress entry by ID."""
        collection = self._get_collection()
        try:
            progress = await collection.find_one({
                "_id": ObjectId(progress_id),
                "user_id": user_id
            })

            if progress:
                return self._format_progress_response(progress)
        except (InvalidId, TypeError):
            return None

        return None

    async def update_progress(
        self,
        progress_id: str,
        user_id: str,
        progress_data: ProgressUpdate
    ) -> ProgressResponse:
        """Update a progress entry."""
        collection = self._get_collection()
        update_data = progress_data.dict(exclude_unset=True)

        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update"
            )

        result = await collection.update_one(
            {
                "_id": ObjectId(progress_id),
                "user_id": user_id
            },
            {"$set": update_data}
        )

        if result.matched_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Progress entry not found"
            )

        updated = await collection.find_one({"_id": ObjectId(progress_id)})
        return self._format_progress_response(updated)

    async def delete_progress(self, progress_id: str, user_id: str) -> bool:
        """Delete a progress entry."""
        collection = self._get_collection()
        result = await collection.delete_one({
            "_id": ObjectId(progress_id),
            "user_id": user_id
        })

        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Progress entry not found"
            )

        return True

    async def get_progress_stats(self, user_id: str, days: int = 30) -> ProgressStats:
        """Calculate progress statistics for a date range."""
        start_date = date.today() - timedelta(days=days)

        progress_list = await self.get_progress_history(
            user_id,
            start_date,
            date.today(),
            0,
            days
        )

        if not progress_list:
            return ProgressStats(
                total_workouts=0,
                total_days_tracked=0,
                avg_weight=None,
                weight_change=None,
                workout_streak=0,
                avg_calories=None,
                avg_calories_burned=None,
                avg_water_intake=None,
                avg_sleep_hours=None,
                avg_steps=None,
                avg_active_minutes=None,
                goal_completion_rate=None,
            )

        total_workouts = sum(1 for p in progress_list if p.workout_completed)
        total_days_tracked = len(progress_list)

        weights = [p.weight for p in progress_list if p.weight is not None]
        avg_weight = sum(weights) / len(weights) if weights else None
        weight_change = (weights[0] - weights[-1]) if len(weights) >= 2 else None

        calories = [p.calories_consumed for p in progress_list if p.calories_consumed is not None]
        avg_calories = sum(calories) / len(calories) if calories else None

        calories_burned = [p.calories_burned for p in progress_list if p.calories_burned is not None]
        avg_calories_burned = sum(calories_burned) / len(calories_burned) if calories_burned else None

        water = [p.water_intake for p in progress_list if p.water_intake is not None]
        avg_water_intake = sum(water) / len(water) if water else None

        sleep = [p.sleep_hours for p in progress_list if p.sleep_hours is not None]
        avg_sleep_hours = sum(sleep) / len(sleep) if sleep else None

        steps = [p.steps for p in progress_list if p.steps is not None]
        avg_steps = sum(steps) / len(steps) if steps else None

        active_minutes = [p.active_minutes for p in progress_list if p.active_minutes is not None]
        avg_active_minutes = sum(active_minutes) / len(active_minutes) if active_minutes else None

        goal_completion = [p.goal_completion for p in progress_list if p.goal_completion is not None]
        goal_completion_rate = sum(goal_completion) / len(goal_completion) if goal_completion else None

        workout_streak = 0
        for p in sorted(progress_list, key=lambda x: x.date, reverse=True):
            if p.workout_completed:
                workout_streak += 1
            else:
                break

        return ProgressStats(
            total_workouts=total_workouts,
            total_days_tracked=total_days_tracked,
            avg_weight=round(avg_weight, 2) if avg_weight else None,
            weight_change=round(weight_change, 2) if weight_change else None,
            workout_streak=workout_streak,
            avg_calories=round(avg_calories, 2) if avg_calories else None,
            avg_calories_burned=round(avg_calories_burned, 2) if avg_calories_burned else None,
            avg_water_intake=round(avg_water_intake, 2) if avg_water_intake else None,
            avg_sleep_hours=round(avg_sleep_hours, 2) if avg_sleep_hours else None,
            avg_steps=round(avg_steps, 2) if avg_steps else None,
            avg_active_minutes=round(avg_active_minutes, 2) if avg_active_minutes else None,
            goal_completion_rate=round(goal_completion_rate, 2) if goal_completion_rate else None,
        )

    def _format_progress_response(self, progress_doc: dict) -> ProgressResponse:
        """Format MongoDB document to ProgressResponse."""
        return ProgressResponse(
            id=str(progress_doc["_id"]),
            user_id=str(progress_doc["user_id"]),
            date=progress_doc["date"],
            weight=progress_doc.get("weight"),
            workout_completed=progress_doc.get("workout_completed", False),
            calories_consumed=progress_doc.get("calories_consumed"),
            calories_burned=progress_doc.get("calories_burned"),
            water_intake=progress_doc.get("water_intake"),
            sleep_hours=progress_doc.get("sleep_hours"),
            steps=progress_doc.get("steps"),
            active_minutes=progress_doc.get("active_minutes"),
            goal_completion=progress_doc.get("goal_completion"),
            notes=progress_doc.get("notes"),
            created_at=progress_doc["created_at"],
        )
