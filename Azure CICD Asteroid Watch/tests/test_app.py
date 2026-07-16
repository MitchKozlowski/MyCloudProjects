"""
Tests for Asteroid Watch.

Key idea: we NEVER call the real NASA API in tests. Instead we use
unittest.mock to replace `requests.get` with a fake that returns
data we control. This makes tests:
  - fast (no real network round-trip)
  - deterministic (NASA's live data changes daily, our fake data doesn't)
  - reliable in CI (GitHub Actions runners shouldn't depend on NASA
    being up, or on secrets being available, just to run tests)

Run with:  pytest
"""

from unittest.mock import patch, Mock

import pytest

from app import app as flask_app


@pytest.fixture
def client():
    """
    A Flask test client - lets us make fake HTTP requests to our app
    in-process, without actually starting a server or opening a port.
    """
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as client:
        yield client


# A minimal but realistic fake NASA response, shaped exactly like the real
# NeoWs feed endpoint's JSON, but with just one asteroid so it's easy to
# reason about in assertions.
FAKE_NASA_RESPONSE = {
    "near_earth_objects": {
        "2026-07-01": [
            {
                "id": "12345",
                "name": "(2026 AB1)",
                "is_potentially_hazardous_asteroid": True,
                "estimated_diameter": {
                    "kilometers": {
                        "estimated_diameter_min": 0.1,
                        "estimated_diameter_max": 0.3,
                    }
                },
                "close_approach_data": [
                    {
                        "relative_velocity": {"kilometers_per_hour": "45000.5"},
                        "miss_distance": {"kilometers": "1234567.8"},
                    }
                ],
            }
        ]
    }
}


class TestHealthCheck:
    def test_healthz_returns_200(self, client):
        response = client.get("/healthz")
        assert response.status_code == 200

    def test_healthz_returns_ok_status(self, client):
        response = client.get("/healthz")
        assert response.get_json() == {"status": "ok"}


class TestDateValidation:
    def test_rejects_range_over_seven_days(self, client):
        response = client.get(
            "/api/asteroids?start_date=2026-07-01&end_date=2026-07-10"
        )
        assert response.status_code == 400
        assert "7 days" in response.get_json()["error"]

    def test_accepts_range_of_exactly_seven_days(self, client):
        # This is a boundary test - 7 days is explicitly allowed by NASA,
        # so we want to make sure our check (`> 7`, not `>= 7`) doesn't
        # accidentally reject the maximum valid range.
        with patch("app.requests.get") as mock_get:
            mock_get.return_value = Mock(
                status_code=200, json=lambda: FAKE_NASA_RESPONSE
            )
            mock_get.return_value.raise_for_status = lambda: None

            response = client.get(
                "/api/asteroids?start_date=2026-07-01&end_date=2026-07-07"
            )
        assert response.status_code == 200


class TestAsteroidParsing:
    def test_parses_nasa_response_into_expected_shape(self, client):
        with patch("app.requests.get") as mock_get:
            mock_get.return_value = Mock(
                status_code=200, json=lambda: FAKE_NASA_RESPONSE
            )
            mock_get.return_value.raise_for_status = lambda: None

            response = client.get(
                "/api/asteroids?start_date=2026-07-01&end_date=2026-07-01"
            )

        assert response.status_code == 200
        data = response.get_json()
        assert data["count"] == 1

        asteroid = data["asteroids"][0]
        # Name should have the surrounding parentheses stripped.
        assert asteroid["name"] == "2026 AB1"
        assert asteroid["is_hazardous"] is True
        assert asteroid["velocity_kph"] == 45000  # rounded
        assert asteroid["miss_distance_km"] == 1234568  # rounded

    def test_handles_empty_nasa_response(self, client):
        with patch("app.requests.get") as mock_get:
            mock_get.return_value = Mock(
                status_code=200, json=lambda: {"near_earth_objects": {}}
            )
            mock_get.return_value.raise_for_status = lambda: None

            response = client.get(
                "/api/asteroids?start_date=2026-07-01&end_date=2026-07-01"
            )

        assert response.status_code == 200
        assert response.get_json()["count"] == 0


class TestNasaFailureHandling:
    def test_returns_502_when_nasa_is_unreachable(self, client):
        import requests

        with patch("app.requests.get") as mock_get:
            mock_get.side_effect = requests.exceptions.ConnectionError(
                "simulated network failure"
            )

            response = client.get(
                "/api/asteroids?start_date=2026-07-01&end_date=2026-07-01"
            )

        assert response.status_code == 502
        assert "error" in response.get_json()
