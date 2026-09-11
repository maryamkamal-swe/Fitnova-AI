"""
MongoDB database connection and management
"""
from datetime import datetime

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from bson import ObjectId
from bson.errors import InvalidId
from pymongo import ASCENDING, DESCENDING, UpdateOne
from pymongo.errors import ConnectionFailure
from .config import settings
import logging
from typing import Any, Dict, List, Optional

try:
    from langchain_core.chat_history import BaseChatMessageHistory
    from langchain_core.messages import AIMessage, BaseMessage, HumanMessage
except ImportError:  # Keep non-RAG services importable without the AI stack.
    class BaseChatMessageHistory:  # type: ignore[no-redef]
        pass

    BaseMessage = object  # type: ignore[assignment]
    AIMessage = None  # type: ignore[assignment]
    HumanMessage = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)


class Database:
    client: AsyncIOMotorClient = None
    db: AsyncIOMotorDatabase = None


db = Database()


async def connect_to_mongodb():
    """Connect to MongoDB Atlas"""
    try:
        logger.info("Connecting to MongoDB...")
        db.client = AsyncIOMotorClient(settings.MONGODB_URI)
        db.db = db.client[settings.DATABASE_NAME]
        
        # Test connection
        await db.client.admin.command('ping')
        await migrate_legacy_user_ids()
        await initialize_indexes()
        logger.info(f"✅ Connected to MongoDB database: {settings.DATABASE_NAME}")
        
    except ConnectionFailure as e:
        logger.error(f"❌ Failed to connect to MongoDB: {e}")
        raise


async def initialize_indexes() -> None:
    """Create the indexes required by authenticated application queries."""
    if db.db is None:
        raise RuntimeError("MongoDB is not connected")

    await db.db.users.create_index(
        [("email", ASCENDING)], name="users_email_unique", unique=True
    )
    await db.db.progress.create_index(
        [("user_id", ASCENDING), ("date", DESCENDING)],
        name="progress_user_date",
    )
    await db.db.food_logs.create_index(
        [("user_id", ASCENDING), ("date", DESCENDING)],
        name="food_logs_user_date",
    )
    await db.db.notifications.create_index(
        [("user_id", ASCENDING), ("created_at", DESCENDING)],
        name="notifications_user_created_at",
    )
    await db.db.meal_plans.create_index(
        [("user_id", ASCENDING)], name="meal_plans_user"
    )
    await db.db.workout_plans.create_index(
        [("user_id", ASCENDING)], name="workout_plans_user"
    )
    await db.db.chat_histories.create_index(
        [("user_id", ASCENDING), ("created_at", DESCENDING)],
        name="chat_histories_user_created_at",
    )
    await db.db.refresh_tokens.create_index(
        [("jti", ASCENDING)], name="refresh_tokens_jti_unique", unique=True
    )
    await db.db.refresh_tokens.create_index(
        [("expires_at", ASCENDING)],
        name="refresh_tokens_expiry_ttl",
        expireAfterSeconds=0,
    )


async def migrate_legacy_user_ids() -> None:
    """Idempotently normalize legacy ObjectId ownership references to strings."""
    if db.db is None:
        raise RuntimeError("MongoDB is not connected")

    collections = (
        "progress",
        "progress_logs",
        "food_logs",
        "notifications",
        "meal_plans",
        "workout_plans",
        "chat_histories",
        "meal_plan_adjustments",
        "refresh_tokens",
    )
    for collection_name in collections:
        collection = db.db[collection_name]
        cursor = collection.find(
            {"user_id": {"$type": "objectId"}}, {"_id": 1, "user_id": 1}
        )
        operations = []
        async for record in cursor:
            operations.append(
                UpdateOne(
                    {"_id": record["_id"], "user_id": record["user_id"]},
                    {"$set": {"user_id": str(record["user_id"])}},
                )
            )
            if len(operations) == 500:
                await collection.bulk_write(operations, ordered=False)
                operations.clear()
        if operations:
            await collection.bulk_write(operations, ordered=False)
            logger.info(
                "Normalized %s legacy ObjectId user_id values in %s",
                len(operations),
                collection_name,
            )


async def close_mongodb_connection():
    """Close MongoDB connection"""
    if db.client:
        db.client.close()
        logger.info("✅ MongoDB connection closed")


def get_database() -> AsyncIOMotorDatabase:
    """Get database instance"""
    return db.db


DEFAULT_RAG_PROFILE: Dict[str, Any] = {
    "name": "FitNova athlete",
    "age": 25,
    "gender": "other",
    "height": 170,
    "weight": 70,
    "fitness_goal": "maintenance",
    "activity_level": "moderate",
    "fitness_experience": "beginner",
    "dietary_preferences": [],
    "medical_conditions": [],
}


async def get_user_profile(user_id: str) -> Optional[Dict[str, Any]]:
    """Return the authenticated user's nested profile for RAG prompts."""
    if not user_id or db.db is None:
        return None

    try:
        user = await db.db.users.find_one({"_id": ObjectId(user_id)})
    except (InvalidId, TypeError):
        user = await db.db.users.find_one({"user_id": user_id})

    if not user:
        return None

    profile = user.get("profile")
    if isinstance(profile, dict) and profile:
        return profile

    # Keep compatibility with older flat user documents.
    flat_profile = {
        key: user[key]
        for key in (
            "age",
            "gender",
            "height",              # <-- Added
            "weight",              # <-- Added
            "fitness_goal",
            "fitness_goals",
            "activity_level",
            "fitness_experience",
            "dietary_preferences",
            "dietary_restrictions",
            "medical_conditions",
            "daily_calories",
        )
        if key in user
    }
    return {**DEFAULT_RAG_PROFILE, **flat_profile}


async def get_chat_history(user_id: str, session_id: str) -> List[Dict[str, str]]:
    """Read chat messages scoped to both the authenticated user and session."""
    if db.db is None:
        return []
    document = await db.db.chat_histories.find_one(
        {"user_id": user_id, "session_id": session_id}
    )
    return document.get("messages", []) if document else []


async def add_chat_message(
    user_id: str, session_id: str, role: str, content: str
) -> None:
    """Persist one chat message without allowing cross-user session access."""
    if db.db is None and user_id == "anonymous":
        return
    if db.db is None:
        raise RuntimeError("MongoDB is not connected")
    await db.db.chat_histories.update_one(
        {"user_id": user_id, "session_id": session_id},
        {
            "$push": {"messages": {"role": role, "content": content}},
            "$set": {"updated_at": datetime.utcnow()},
            "$setOnInsert": {"created_at": datetime.utcnow()},
        },
        upsert=True,
    )


class MongoChatMessageHistory(BaseChatMessageHistory):
    def __init__(self, user_id: str, session_id: str):
        if HumanMessage is None or AIMessage is None:
            raise RuntimeError(
                "langchain-core is required for MongoChatMessageHistory"
            )
        self.user_id = user_id
        self.session_id = session_id
        self._cached_messages: List[BaseMessage] = []

    @property
    def messages(self) -> List[BaseMessage]:
        return self._cached_messages

    async def aget_messages(self) -> List[BaseMessage]:
        history = await get_chat_history(self.user_id, self.session_id)
        self._cached_messages = [
            HumanMessage(content=item["content"])
            if item.get("role") == "human"
            else AIMessage(content=item["content"])
            for item in history
            if item.get("role") in {"human", "ai"}
        ]
        return self._cached_messages

    def add_message(self, message: BaseMessage) -> None:
        self._cached_messages.append(message)

    async def aadd_messages(self, messages: List[BaseMessage]) -> None:
        for message in messages:
            role = "human" if isinstance(message, HumanMessage) else "ai"
            await add_chat_message(
                self.user_id, self.session_id, role, str(message.content)
            )
            self._cached_messages.append(message)

    def clear(self) -> None:
        self._cached_messages = []
