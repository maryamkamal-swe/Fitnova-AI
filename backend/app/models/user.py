# backend/app/models/user.py
"""
User models and schemas
"""
from pydantic import BaseModel, EmailStr, Field, field_validator, ConfigDict
from typing import Optional, List
from datetime import datetime
from enum import Enum


class Gender(str, Enum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"


class FitnessGoal(str, Enum):
    WEIGHT_LOSS = "weight_loss"
    MUSCLE_GAIN = "muscle_gain"
    MAINTENANCE = "maintenance"
    ENDURANCE = "endurance"
    FLEXIBILITY = "flexibility"


class ActivityLevel(str, Enum):
    SEDENTARY = "sedentary"
    LIGHT = "light"
    MODERATE = "moderate"
    ACTIVE = "active"
    VERY_ACTIVE = "very_active"


class FitnessExperience(str, Enum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class UserProfile(BaseModel):
    """User profile information"""
    name: str = Field(..., min_length=2, max_length=100)
    age: int = Field(..., ge=13, le=100)
    gender: Gender
    height: float = Field(..., gt=0, description="Height in cm")
    weight: float = Field(..., gt=0, description="Weight in kg")
    fitness_goal: FitnessGoal
    activity_level: ActivityLevel
    fitness_experience: FitnessExperience
    dietary_preferences: Optional[List[str]] = []
    medical_conditions: Optional[List[str]] = []
    
    @field_validator('height')
    @classmethod
    def validate_height(cls, v: float) -> float:
        if v < 50 or v > 300:
            raise ValueError('Height must be between 50-300 cm')
        return v
    
    @field_validator('weight')
    @classmethod
    def validate_weight(cls, v: float) -> float:
        if v < 20 or v > 300:
            raise ValueError('Weight must be between 20-300 kg')
        return v


class UserCreate(BaseModel):
    """Schema for user registration"""
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=100)
    profile: Optional[UserProfile] = None
    
    @field_validator('password')
    @classmethod
    def validate_password(cls, v: str) -> str:
        if not any(char.isdigit() for char in v):
            raise ValueError('Password must contain at least one digit')
        if not any(char.isupper() for char in v):
            raise ValueError('Password must contain at least one uppercase letter')
        return v


class UserLogin(BaseModel):
    """Schema for user login"""
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    """Response model for user data"""
    id: str
    email: EmailStr
    profile: Optional[UserProfile] = None
    profile_complete: bool = False
    created_at: datetime
    updated_at: datetime
    
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "id": "507f1f77bcf86cd799439011",
                "email": "user@example.com",
                "profile": {
                    "name": "John Doe",
                    "age": 25,
                    "gender": "male",
                    "height": 175.0,
                    "weight": 70.0,
                    "fitness_goal": "muscle_gain",
                    "activity_level": "moderate",
                    "fitness_experience": "intermediate"
                },
                "created_at": "2026-08-12T10:00:00",
                "updated_at": "2026-08-12T10:00:00"
            }
        }
    )


class UserUpdate(BaseModel):
    """Schema for updating user profile"""
    profile: Optional[UserProfile] = None


class TokenResponse(BaseModel):
    """JWT token response"""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RegistrationResponse(BaseModel):
    """Registration result before email verification."""
    email: EmailStr
    message: str
    delivered: bool
    development_code: Optional[str] = None


class TokenRefresh(BaseModel):
    """Schema for token refresh"""
    refresh_token: str


class PasswordChange(BaseModel):
    """Schema for password change"""
    old_password: str
    new_password: str = Field(..., min_length=8, max_length=100)