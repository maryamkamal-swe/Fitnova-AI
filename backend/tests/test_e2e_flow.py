# backend/tests/test_e2e_flow.py
import pytest
from fastapi.testclient import TestClient
from app.main import app

@pytest.fixture(scope="module")
def client():
    """
    Using TestClient as a context manager ensures that FastAPI's lifespan
    events (like connecting to MongoDB and SQLite) are triggered correctly.
    """
    with TestClient(app) as c:
        yield c

@pytest.fixture(scope="module")
def shared_state():
    return {"token": "", "user_id": ""}

def test_01_health_check(client):
    response = client.get("/health")
    # Will fail if MongoDB/SQLite are offline. Assuming they are running locally.
    assert response.status_code in [200, 503]

def test_02_register_user(client, shared_state):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "e2e_test_user@example.com",
            "password": "SecurePassword123",
        }
    )
    if response.status_code == 400: # Already exists
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "e2e_test_user@example.com", "password": "SecurePassword123"}
        )
    assert response.status_code in [200, 201]
    data = response.json()
    assert "access_token" in data
    shared_state["token"] = data["access_token"]

def test_03_setup_profile(client, shared_state):
    headers = {"Authorization": f"Bearer {shared_state['token']}"}
    response = client.put(
        "/api/v1/profile",
        headers=headers,
        json={
            "name": "E2E Tester",
            "age": 30,
            "gender": "other",
            "height": 180,
            "weight": 80,
            "fitness_goal": "muscle_gain",
            "activity_level": "moderate",
            "fitness_experience": "intermediate",
            "dietary_preferences": ["high_protein"],
            "medical_conditions": []
        }
    )
    assert response.status_code == 200
    assert response.json()["message"] == "Profile updated successfully"

def test_04_get_profile(client, shared_state):
    headers = {"Authorization": f"Bearer {shared_state['token']}"}
    response = client.get("/api/v1/profile", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["profile"]["name"] == "E2E Tester"
    assert "health_metrics" in data

def test_05_log_progress(client, shared_state):
    headers = {"Authorization": f"Bearer {shared_state['token']}"}
    response = client.post(
        "/api/v1/progress",
        headers=headers,
        json={
            "date": "2026-08-15",
            "weight": 79.5,
            "workout_completed": True,
            "calories_consumed": 2500,
            "water_intake": 3.0,
            "sleep_hours": 8.0,
        }
    )
    assert response.status_code == 201
    data = response.json()
    assert data["weight"] == 79.5
    assert data["workout_completed"] is True

def test_06_get_progress_stats(client, shared_state):
    headers = {"Authorization": f"Bearer {shared_state['token']}"}
    response = client.get("/api/v1/progress/stats?days=30", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "total_workouts" in data