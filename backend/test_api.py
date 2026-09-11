"""
Quick API test script
Run this after starting the server to test endpoints
"""
import requests
import json

BASE_URL = "http://localhost:8000/api/v1"

def print_response(title, response):
    """Pretty print response"""
    print(f"\n{'='*60}")
    print(f"{title}")
    print(f"{'='*60}")
    print(f"Status Code: {response.status_code}")
    try:
        print(f"Response: {json.dumps(response.json(), indent=2)}")
    except:
        print(f"Response: {response.text}")


def api_check_health():
    """Test health endpoint"""
    response = requests.get("http://localhost:8000/health")
    print_response("HEALTH CHECK", response)


def api_check_register():
    """Test user registration"""
    data = {
        "email": "test@fitnova.com",
        "password": "Test1234",
        "profile": {
            "name": "John Doe",
            "age": 25,
            "gender": "male",
            "height": 175.0,
            "weight": 70.0,
            "fitness_goal": "muscle_gain",
            "activity_level": "moderate",
            "fitness_experience": "intermediate",
            "dietary_preferences": ["high_protein"],
            "medical_conditions": []
        }
    }
    
    response = requests.post(f"{BASE_URL}/auth/register", json=data)
    print_response("REGISTER USER", response)
    
    if response.status_code == 201:
        return response.json()["access_token"]
    return None


def api_check_login():
    """Test user login"""
    data = {
        "email": "test@fitnova.com",
        "password": "Test1234"
    }
    
    response = requests.post(f"{BASE_URL}/auth/login", json=data)
    print_response("LOGIN USER", response)
    
    if response.status_code == 200:
        return response.json()["access_token"]
    return None


def api_check_profile(token):
    """Test get profile"""
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(f"{BASE_URL}/profile", headers=headers)
    print_response("GET PROFILE", response)


def api_check_log_progress(token):
    """Test logging progress"""
    headers = {"Authorization": f"Bearer {token}"}
    data = {
        "date": "2026-08-12",
        "weight": 70.5,
        "workout_completed": True,
        "calories_consumed": 2200,
        "water_intake": 2.5,
        "sleep_hours": 7.5,
        "notes": "Great workout today!"
    }
    
    response = requests.post(f"{BASE_URL}/progress", json=data, headers=headers)
    print_response("LOG PROGRESS", response)


def api_check_progress_stats(token):
    """Test getting progress statistics"""
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(f"{BASE_URL}/progress/stats?days=30", headers=headers)
    print_response("GET PROGRESS STATS", response)


def main():
    """Run all tests"""
    print("\n🚀 Starting FitNova AI API Tests")
    print("Make sure the server is running on http://localhost:8000\n")
    
    # Test health
    api_check_health()
    
    # Test registration
    token = api_check_register()
    
    if not token:
        # If registration fails (user exists), try login
        print("\n⚠️ Registration failed, trying login...")
        token = api_check_login()
    
    if token:
        # Test protected endpoints
        api_check_profile(token)
        api_check_log_progress(token)
        api_check_progress_stats(token)
        
        print("\n✅ All tests completed!")
        print(f"\n🔑 Access Token:\n{token}")
    else:
        print("\n❌ Failed to get access token")


if __name__ == "__main__":
    main()
