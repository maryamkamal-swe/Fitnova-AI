from fastapi.testclient import TestClient

from app.main import app


def test_any_origin_can_complete_auth_preflight():
    response = TestClient(app).options(
        "/api/v1/auth/login",
        headers={
            "Origin": "https://demo.example.com",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "*"
    assert "access-control-allow-credentials" not in response.headers
