"""
Custom validators for data validation
"""
from datetime import date
from typing import Optional

from app.models.user import ActivityLevel
from app.services.calorie_service import calculate_bmr, calculate_tdee as _calculate_tdee


def validate_date_range(start_date: Optional[date], end_date: Optional[date]) -> tuple:
    """
    Validate date range for queries
    
    Args:
        start_date: Start date
        end_date: End date
    
    Returns:
        Tuple of (start_date, end_date)
    
    Raises:
        ValueError: If date range is invalid
    """
    if start_date and end_date:
        if start_date > end_date:
            raise ValueError("start_date must be before end_date")
        
        if end_date > date.today():
            raise ValueError("end_date cannot be in the future")
    
    return start_date, end_date


def validate_pagination(skip: int, limit: int) -> tuple:
    """
    Validate pagination parameters
    
    Args:
        skip: Number of records to skip
        limit: Maximum number of records to return
    
    Returns:
        Tuple of (skip, limit)
    
    Raises:
        ValueError: If pagination parameters are invalid
    """
    if skip < 0:
        raise ValueError("skip must be >= 0")
    
    if limit < 1:
        raise ValueError("limit must be >= 1")
    
    if limit > 100:
        raise ValueError("limit must be <= 100")
    
    return skip, limit


def calculate_bmi(weight: float, height: float) -> float:
    """
    Calculate BMI (Body Mass Index)
    
    Args:
        weight: Weight in kg
        height: Height in cm
    
    Returns:
        BMI value
    """
    height_m = height / 100  # Convert cm to meters
    bmi = weight / (height_m ** 2)
    return round(bmi, 2)


def get_bmi_category(bmi: float) -> str:
    """
    Get BMI category
    
    Args:
        bmi: BMI value
    
    Returns:
        BMI category string
    """
    if bmi < 18.5:
        return "Underweight"
    elif bmi < 23:
        return "Normal weight"
    elif bmi < 27.5:
        return "Increased Risk / Overweight"
    else:
        return "High Risk / Obese"


def calculate_tdee(bmr: float, activity_level: str) -> float:
    """
    Calculate Total Daily Energy Expenditure
    
    Args:
        bmr: Basal Metabolic Rate
        activity_level: Activity level (sedentary, light, moderate, active, very_active)
    
    Returns:
        TDEE in calories/day
    """
    try:
        level = ActivityLevel(str(activity_level).lower())
    except ValueError:
        level = ActivityLevel.SEDENTARY
    return round(_calculate_tdee(bmr, level), 2)
