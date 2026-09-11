"""
Custom validators for data validation
"""
from datetime import date, datetime
from typing import Optional


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
    elif 18.5 <= bmi < 25:
        return "Normal weight"
    elif 25 <= bmi < 30:
        return "Overweight"
    else:
        return "Obese"


def calculate_bmr(weight: float, height: float, age: int, gender: str) -> float:
    """
    Calculate Basal Metabolic Rate using Mifflin-St Jeor Equation
    
    Args:
        weight: Weight in kg
        height: Height in cm
        age: Age in years
        gender: Gender (male/female)
    
    Returns:
        BMR in calories/day
    """
    # Mifflin-St Jeor Equation
    bmr = 10 * weight + 6.25 * height - 5 * age
    
    if gender.lower() == "male":
        bmr += 5
    else:
        bmr -= 161
    
    return round(bmr, 2)


def calculate_tdee(bmr: float, activity_level: str) -> float:
    """
    Calculate Total Daily Energy Expenditure
    
    Args:
        bmr: Basal Metabolic Rate
        activity_level: Activity level (sedentary, light, moderate, active, very_active)
    
    Returns:
        TDEE in calories/day
    """
    activity_multipliers = {
        "sedentary": 1.2,      # Little or no exercise
        "light": 1.375,        # Light exercise 1-3 days/week
        "moderate": 1.55,      # Moderate exercise 3-5 days/week
        "active": 1.725,       # Heavy exercise 6-7 days/week
        "very_active": 1.9     # Very heavy exercise, physical job
    }
    
    multiplier = activity_multipliers.get(activity_level.lower(), 1.2)
    tdee = bmr * multiplier
    
    return round(tdee, 2)
