import asyncio
import os
import sys

# Add project root to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.db.mongo import get_db


async def seed_demo_user():
    db = get_db()
    test_user = {
        "user_id": "demo-user",
        "name": "Demo User",
        "age": 24,
        "gender": "female",
        "fitness_goals": "muscle building and endurance",
        "dietary_restrictions": "dairy-free",
        "daily_calories": 2200,
    }
    
    await db.users.update_one(
        {"user_id": "demo-user"},
        {"$set": test_user},
        upsert=True
    )
    print("Successfully created/updated 'demo-user' in MongoDB Atlas!")


if __name__ == "__main__":
    asyncio.run(seed_demo_user())