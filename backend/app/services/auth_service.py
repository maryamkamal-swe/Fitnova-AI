# backend/app/services/auth_service.py
import hashlib
import logging
from datetime import datetime, timezone
from typing import Optional
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException, status
from pymongo import ReturnDocument
from pymongo.errors import PyMongoError
from ..database import get_database
from ..models.user import (
    RegistrationResponse,
    UserCreate,
    UserLogin,
    UserResponse,
    TokenResponse,
)
from .otp_service import issue_otp
from ..utils.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
    decode_token,
)

logger = logging.getLogger(__name__)


class AuthService:
    def __init__(self):
        self.db = None
        self.users_collection = None
    
    def _get_collection(self):
        if self.users_collection is None:
            self.db = get_database()
            self.users_collection = self.db.users
        return self.users_collection

    async def _issue_tokens(self, user_id: str) -> TokenResponse:
        self._get_collection()
        access_token = create_access_token(data={"sub": user_id})
        refresh_token = create_refresh_token(data={"sub": user_id})
        payload = decode_token(refresh_token)
        expires_at = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
        await self.db.refresh_tokens.insert_one({
            "user_id": user_id,
            "jti": payload["jti"],
            "token_hash": hashlib.sha256(refresh_token.encode("utf-8")).hexdigest(),
            "expires_at": expires_at,
            "revoked": False,
            "created_at": datetime.now(timezone.utc),
        })
        return TokenResponse(access_token=access_token, refresh_token=refresh_token)

    async def revoke_user_refresh_tokens(self, user_id: str) -> None:
        self._get_collection()
        await self.db.refresh_tokens.update_many(
            {"user_id": user_id, "revoked": False},
            {"$set": {"revoked": True, "revoked_at": datetime.now(timezone.utc)}},
        )
    
    async def register_user(self, user_data: UserCreate) -> RegistrationResponse:
        collection = self._get_collection()
        email = str(user_data.email).lower().strip()
        existing_user = await collection.find_one({"email": email})
        if existing_user:
            if existing_user.get("email_verified") is not True:
                otp_result = await issue_otp(email)
                return RegistrationResponse(
                    email=email,
                    message="A new verification code has been sent. Please verify your email with OTP.",
                    delivered=otp_result["delivered"],
                    development_code=otp_result.get("development_code"),
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        
        hashed_password = hash_password(user_data.password)
        
        user_doc = {
            "email": email,
            "password_hash": hashed_password,
            "profile": user_data.profile.model_dump(mode="json") if user_data.profile else {},
            "profile_complete": user_data.profile is not None,
            "email_verified": False,
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow()
        }
        
        result = await collection.insert_one(user_doc)
        try:
            otp_result = await issue_otp(email)
        except RuntimeError as error:
            await collection.delete_one({"_id": result.inserted_id})
            await self.db.otps.delete_many({"email": email})
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Email delivery is currently unavailable. Please try again later.",
            ) from error
        return RegistrationResponse(
            email=email,
            message="Registration successful. Please verify your email with OTP.",
            delivered=otp_result["delivered"],
            development_code=otp_result.get("development_code"),
        )

    async def mark_email_verified(self, email: str) -> Optional[str]:
        """Persist successful email verification for the matching user."""
        collection = self._get_collection()
        user = await collection.find_one_and_update(
            {"email": email.lower().strip(), "email_verified": {"$ne": True}},
            {
                "$set": {
                    "email_verified": True,
                    "updated_at": datetime.utcnow(),
                }
            },
            return_document=ReturnDocument.AFTER,
        )
        return str(user["_id"]) if user else None
    
    async def login_user(self, login_data: UserLogin) -> TokenResponse:
        collection = self._get_collection()
        user = await collection.find_one({"email": str(login_data.email).lower().strip()})
        
        if not user or not verify_password(login_data.password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )
        
        if user.get("email_verified") is not True:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email not verified. Please verify your email with OTP before logging in.",
            )

        user_id = str(user["_id"])
        return await self._issue_tokens(user_id)
    
    async def refresh_access_token(self, refresh_token: str) -> TokenResponse:
        collection = self._get_collection()
        user_id = verify_refresh_token(refresh_token)
        
        payload = decode_token(refresh_token)
        token_id = payload.get("jti")
        if not token_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
            
        token_hash = hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()
        stored_token = await self.db.refresh_tokens.find_one({
            "user_id": user_id,
            "jti": token_id,
            "token_hash": token_hash,
            "revoked": False,
        })
        if not stored_token:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

        try:
            object_id = ObjectId(user_id)
        except (InvalidId, TypeError):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user ID format")
            
        user = await collection.find_one({"_id": object_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found"
            )
        if user.get("email_verified") is not True:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email not verified. Please verify your email with OTP before logging in.",
            )
        
        await self.db.refresh_tokens.update_one(
            {"_id": stored_token["_id"]},
            {"$set": {"revoked": True, "revoked_at": datetime.now(timezone.utc)}},
        )
        return await self._issue_tokens(user_id)
    
    async def get_user_by_id(self, user_id: str) -> Optional[dict]:
        collection = self._get_collection()
        try:
            object_id = ObjectId(user_id)
        except (InvalidId, TypeError):
            return None
            
        try:
            user = await collection.find_one({"_id": object_id})
            if user is None:
                return None
            user["id"] = str(user["_id"])
            del user["_id"]
            del user["password_hash"]
            return user
        except PyMongoError as error:
            logger.exception(
                "MongoDB failure while loading user profile for user_id=%s: %s",
                user_id,
                error,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="User service is temporarily unavailable",
            ) from error
        except (KeyError, TypeError, AttributeError) as error:
            logger.error(
                "Data-integrity error: malformed user document for user_id=%s: %s",
                user_id,
                error,
                exc_info=True,
            )
            return None
        except Exception as error:
            logger.exception(
                "Unexpected user profile lookup failure for user_id=%s: %s",
                user_id,
                error,
            )
            return None
    
    async def update_user_profile(self, user_id: str, profile_data: dict) -> bool:
        collection = self._get_collection()
        try:
            object_id = ObjectId(user_id)
        except (InvalidId, TypeError):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
            
        result = await collection.update_one(
            {"_id": object_id},
            {
                "$set": {
                    "profile": profile_data,
                    "profile_complete": True,
                    "updated_at": datetime.utcnow()
                }
            }
        )
        
        if result.matched_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        return True
    
    async def change_password(self, user_id: str, old_password: str, new_password: str) -> bool:
        collection = self._get_collection()
        try:
            object_id = ObjectId(user_id)
        except (InvalidId, TypeError):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
            
        user = await collection.find_one({"_id": object_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        if not verify_password(old_password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Incorrect current password"
            )
        
        new_password_hash = hash_password(new_password)
        await collection.update_one(
            {"_id": object_id},
            {
                "$set": {
                    "password_hash": new_password_hash,
                    "updated_at": datetime.utcnow()
                }
            }
        )
        await self.revoke_user_refresh_tokens(user_id)
        return True
    
    async def delete_user(self, user_id: str) -> bool:
        collection = self._get_collection()
        try:
            object_id = ObjectId(user_id)
        except (InvalidId, TypeError) as error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid user identifier",
            ) from error

        related_filter = {"$in": [user_id, object_id]}
        database = self.db
        for collection_name in (
            "progress",
            "progress_logs",
            "food_logs",
            "meal_plans",
            "workout_plans",
            "notifications",
            "chat_histories",
            "meal_plan_adjustments",
            "refresh_tokens",
        ):
            await database[collection_name].delete_many(
                {"user_id": related_filter}
            )

        result = await collection.delete_one({"_id": object_id})
        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        return True