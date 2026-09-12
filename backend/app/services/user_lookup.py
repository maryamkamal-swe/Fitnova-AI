from bson import ObjectId
from bson.errors import InvalidId

async def get_user_profile(db, user_id: str) -> dict:
    try:
        oid = ObjectId(user_id)
    except InvalidId:
        raise ValueError(f"'{user_id}' is not a valid user id")

    user_doc = await db.users.find_one({"_id": oid})
    if not user_doc:
        raise ValueError(f"No user found with id '{user_id}'")
        
    profile = user_doc.get("profile")
    default_profile = {
        "name": user_doc.get("email", "Athlete").split("@")[0],
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

    if not isinstance(profile, dict):
        return default_profile

    # Merge default values with the fetched profile to prevent downstream KeyErrors
    return {**default_profile, **profile}