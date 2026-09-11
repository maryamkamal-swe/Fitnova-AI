import random
from datetime import date, timedelta
import requests

# Set your backend URL (or use http://127.0.0.1:8000 for local dev)
BASE_URL = "https://fitnova-ai-dv0n.onrender.com/api/v1"

# Account Credentials
EMAIL = "maryamkamal.email@gmail.com"
PASSWORD = "123456@Mm"

# Configuration: How many days of historical progress to generate
DAYS_TO_SEED = 14


def get_auth_token(email: str, password: str) -> str:
    """Log in and return JWT bearer token."""
    response = requests.post(
        f"{BASE_URL}/auth/login",
        json={"email": email, "password": password},
        headers={"Content-Type": "application/json"},
    )
    if response.status_code != 200:
        raise RuntimeError(f"Login failed: {response.status_code} - {response.text}")

    data = response.json()
    # Check common JWT payload locations
    token = data.get("access_token") or data.get("token") or data.get("data", {}).get("access_token")
    if not token:
        raise RuntimeError(f"Token not found in login response: {data}")
    return token


def seed_progress_data(token: str, days: int = 14):
    """Generate and post daily progress entries."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    start_date = date.today() - timedelta(days=days - 1)
    base_weight = 75.0  # Starting weight in kg

    print(f"🚀 Populating {days} days of progress data starting from {start_date}...\n")

    for i in range(days):
        current_date = start_date + timedelta(days=i)
        
        # Simulate realistic daily progress metrics
        base_weight -= random.choice([0.0, 0.1, -0.05, 0.15])  # Gradual weight trend
        workout_done = random.choice([True, True, True, False])  # ~75% workout completion
        
        payload = {
            "date": str(current_date),
            "weight": round(base_weight, 1),
            "workout_completed": workout_done,
            "calories_consumed": random.randint(1900, 2400),
            "calories_burned": random.randint(350, 600) if workout_done else random.randint(100, 200),
            "water_intake": round(random.uniform(2.0, 3.5), 1),
            "sleep_hours": round(random.uniform(6.5, 8.5), 1),
            "steps": random.randint(6500, 12000),
            "active_minutes": random.randint(40, 75) if workout_done else random.randint(10, 25),
            "goal_completion": round(random.uniform(70.0, 100.0), 1),
            "notes": f"Logged via automated seed script for day {i + 1}.",
        }

        res = requests.post(f"{BASE_URL}/progress", json=payload, headers=headers)

        if res.status_code == 21:
            print(f"✅ [{current_date}] Progress logged successfully.")
        elif res.status_code in (200, 201):
            print(f"✅ [{current_date}] Progress logged successfully.")
        else:
            print(f"⚠️ [{current_date}] Failed ({res.status_code}): {res.text}")


if __name__ == "__main__":
    try:
        jwt_token = get_auth_token(EMAIL, PASSWORD)
        print("🔑 Authentication successful.")
        seed_progress_data(jwt_token, days=DAYS_TO_SEED)
        print("\n🎉 Seeding complete! Refresh your frontend app or view the progress charts.")
    except Exception as e:
        print(f"❌ Error: {e}")