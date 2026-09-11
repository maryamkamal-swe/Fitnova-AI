"""
User profile routes
Handles profile CRUD operations
"""
from fastapi import APIRouter, HTTPException, Request, status, Depends
from ..models.user import UserProfile, UserUpdate
from ..services.auth_service import AuthService
from ..utils.security import get_current_user_id
from ..core.limiter import limiter
from ..utils.validators import calculate_bmi, get_bmi_category, calculate_bmr, calculate_tdee

router = APIRouter(prefix="/profile", tags=["User Profile"])
auth_service = AuthService()


@router.get("")
async def get_profile(user_id: str = Depends(get_current_user_id)):
    """
    Get user profile
    
    Requires authentication
    Returns complete user profile with health metrics
    """
    user = await auth_service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    if not user.get("profile_complete", bool(user.get("profile"))):
        return user

    profile = user.get("profile") if isinstance(user.get("profile"), dict) else {}
    weight = profile.get("weight") or 70
    height = profile.get("height") or 170
    age = profile.get("age") or 25
    gender = str(profile.get("gender") or "other")
    activity_level = str(profile.get("activity_level") or "moderate")
    bmi = calculate_bmi(weight, height)
    bmi_category = get_bmi_category(bmi)
    bmr = calculate_bmr(weight, height, age, gender)
    tdee = calculate_tdee(bmr, activity_level)
    
    # Add calculated metrics to response
    user["health_metrics"] = {
        "bmi": bmi,
        "bmi_category": bmi_category,
        "bmr": bmr,
        "tdee": tdee
    }
    
    return user


@router.put("")
async def update_profile(
    profile_data: UserProfile,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update user profile
    
    - **profile**: Complete updated profile data
    
    Requires authentication
    """
    await auth_service.update_user_profile(user_id, profile_data.dict())
    return {"message": "Profile updated successfully"}


@router.delete("")
@limiter.limit("3/hour")
async def delete_profile(request: Request, user_id: str = Depends(get_current_user_id)):
    """
    Delete user account
    
    ⚠️ WARNING: This action is irreversible
    Deletes all user data including profile, workout plans, meal plans, and progress history
    
    Requires authentication
    """
    await auth_service.delete_user(user_id)
    return {"message": "Account deleted successfully"}


@router.get("/health-metrics")
async def get_health_metrics(user_id: str = Depends(get_current_user_id)):
    """
    Get calculated health metrics
    
    Returns:
    - BMI (Body Mass Index)
    - BMI Category
    - BMR (Basal Metabolic Rate)
    - TDEE (Total Daily Energy Expenditure)
    
    Requires authentication
    """
    user = await auth_service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    profile = user.get("profile") if isinstance(user.get("profile"), dict) else {}

    weight = profile.get("weight") or 70
    height = profile.get("height") or 170
    age = profile.get("age") or 25
    gender = str(profile.get("gender") or "other")
    activity_level = str(profile.get("activity_level") or "moderate")

    bmi = calculate_bmi(weight, height)
    bmi_category = get_bmi_category(bmi)
    bmr = calculate_bmr(weight, height, age, gender)
    tdee = calculate_tdee(bmr, activity_level)
    
    return {
        "bmi": bmi,
        "bmi_category": bmi_category,
        "bmr": bmr,
        "tdee": tdee,
        "description": {
            "bmi": "Body Mass Index - Measure of body fat based on height and weight",
            "bmr": "Basal Metabolic Rate - Calories burned at rest per day",
            "tdee": "Total Daily Energy Expenditure - Total calories burned per day including activity"
        }
    }
