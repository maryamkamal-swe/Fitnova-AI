"""
Authentication service
Handles user registration, login, and token management
"""
import hashlib
from datetime import datetime, timezone
from typing import Optional
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException, status
from ..database import get_database
from ..models.user import UserCreate, UserLogin, UserResponse, TokenResponse
from ..utils.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
    decode_token,
)


class AuthService:
    def __init__(self):
        self.db = None
        self.users_collection = None
    
    def _get_collection(self):
        """Lazy load database collection"""
        if self.users_collection is None:
            self.db = get_database()
            self.users_collection = self.db.users
        return self.users_collection

    async def _issue_tokens(self, user_id: str) -> TokenResponse:
        """Issue a token pair and persist only a fingerprint of the refresh token."""
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
        """Invalidate all refresh tokens for a user, including tokens on other devices."""
        self._get_collection()
        await self.db.refresh_tokens.update_many(
            {"user_id": user_id, "revoked": False},
            {"$set": {"revoked": True, "revoked_at": datetime.now(timezone.utc)}},
        )
    
    async def register_user(self, user_data: UserCreate) -> TokenResponse:
        """
        Register a new user
        
        Args:
            user_data: User registration data
        
        Returns:
            JWT tokens
        
        Raises:
            HTTPException: If email already exists
        """
        collection = self._get_collection()
        
        # Check if user already exists
        existing_user = await collection.find_one({"email": user_data.email})
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        
        # Hash password
        hashed_password = hash_password(user_data.password)
        
        # Prepare user document
        user_doc = {
            "email": user_data.email,
            "password_hash": hashed_password,
            "profile": user_data.profile.dict() if user_data.profile else {},
            "profile_complete": user_data.profile is not None,
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow()
        }
        
        # Insert user
        result = await collection.insert_one(user_doc)
        user_id = str(result.inserted_id)
        
        # Generate tokens
        return await self._issue_tokens(user_id)
    
    async def login_user(self, login_data: UserLogin) -> TokenResponse:
        """
        Authenticate user and generate tokens
        
        Args:
            login_data: User login credentials
        
        Returns:
            JWT tokens
        
        Raises:
            HTTPException: If credentials are invalid
        """
        collection = self._get_collection()
        
        # Find user
        user = await collection.find_one({"email": login_data.email})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )
        
        # Verify password
        if not verify_password(login_data.password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )
        
        # Generate tokens
        user_id = str(user["_id"])
        return await self._issue_tokens(user_id)
    
    async def refresh_access_token(self, refresh_token: str) -> TokenResponse:
        """
        Generate new access token using refresh token
        
        Args:
            refresh_token: Valid refresh token
        
        Returns:
            New JWT tokens
        
        Raises:
            HTTPException: If refresh token is invalid
        """
        collection = self._get_collection()
        
        # Verify refresh token
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

        # Verify user still exists
        user = await collection.find_one({"_id": ObjectId(user_id)})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found"
            )
        
        await self.db.refresh_tokens.update_one(
            {"_id": stored_token["_id"]},
            {"$set": {"revoked": True, "revoked_at": datetime.now(timezone.utc)}},
        )
        return await self._issue_tokens(user_id)
    
    async def get_user_by_id(self, user_id: str) -> Optional[dict]:
        """
        Get user by ID
        
        Args:
            user_id: User ID
        
        Returns:
            User document or None
        """
        collection = self._get_collection()
        try:
            user = await collection.find_one({"_id": ObjectId(user_id)})
            if user:
                user["id"] = str(user["_id"])
                del user["_id"]
                del user["password_hash"]  # Never expose password hash
            return user
        except Exception:
            return None
    
    async def update_user_profile(self, user_id: str, profile_data: dict) -> bool:
        """
        Update user profile
        
        Args:
            user_id: User ID
            profile_data: Updated profile data
        
        Returns:
            True if successful
        
        Raises:
            HTTPException: If user not found
        """
        collection = self._get_collection()
        result = await collection.update_one(
            {"_id": ObjectId(user_id)},
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
        """
        Change user password
        
        Args:
            user_id: User ID
            old_password: Current password
            new_password: New password
        
        Returns:
            True if successful
        
        Raises:
            HTTPException: If old password is incorrect
        """
        collection = self._get_collection()
        user = await collection.find_one({"_id": ObjectId(user_id)})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Verify old password
        if not verify_password(old_password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Incorrect current password"
            )
        
        # Update password
        new_password_hash = hash_password(new_password)
        await collection.update_one(
            {"_id": ObjectId(user_id)},
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
        """
        Delete user account
        
        Args:
            user_id: User ID
        
        Returns:
            True if successful
        """
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
