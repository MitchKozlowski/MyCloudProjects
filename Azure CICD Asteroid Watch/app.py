"""
Asteroid Watch - a small Flask app that visualizes NASA's Near Earth Object
(NeoWs) data as an interactive bubble chart.

Architecture note: the NASA API key lives ONLY on the server (loaded from an
environment variable). The browser never sees it - it talks to our own
/api/asteroids endpoint, and we proxy the real request to NASA from here.
This is the same pattern you'll use with Azure Key Vault / App Service
configuration later: secrets stay server-side, never shipped to the client.
"""

import os
from datetime import date, timedelta

import requests
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

NASA_API_KEY = os.environ.get("NASA_API_KEY", "DEMO_KEY")
NASA_NEO_FEED_URL = "https://api.nasa.gov/neo/rest/v1/feed"


@app.route("/")
def index():
    """Serve the single-page app."""
    return render_template("index.html")


@app.route("/healthz")
def healthz():
    """
    Simple health check endpoint.
    Trivial today, but this is exactly what Azure App Service / Container
    Apps health probes will call to know if your app is alive and ready
    for traffic.
    """
    return jsonify(status="ok"), 200


@app.route("/api/asteroids")
def get_asteroids():
    """
    Fetch near-Earth asteroid data from NASA for a date range and return a
    simplified JSON payload the frontend can chart directly.

    Query params:
        start_date (YYYY-MM-DD, optional - defaults to today)
        end_date   (YYYY-MM-DD, optional - defaults to start_date + 6 days)

    NASA's feed endpoint caps ranges at 7 days per request.
    """
    start_date_str = request.args.get("start_date")
    end_date_str = request.args.get("end_date")

    if start_date_str:
        start = date.fromisoformat(start_date_str)
    else:
        start = date.today()

    if end_date_str:
        end = date.fromisoformat(end_date_str)
    else:
        end = start + timedelta(days=6)

    # Enforce NASA's 7-day max range so we fail fast with a clear error
    # instead of NASA rejecting the request.
    if (end - start).days > 7:
        return jsonify(error="Date range cannot exceed 7 days"), 400

    params = {
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "api_key": NASA_API_KEY,
    }

    try:
        response = requests.get(NASA_NEO_FEED_URL, params=params, timeout=10)
        response.raise_for_status()
    except requests.exceptions.RequestException as exc:
        return jsonify(error=f"Failed to fetch data from NASA: {exc}"), 502

    raw = response.json()
    asteroids = []

    for day, objects in raw.get("near_earth_objects", {}).items():
        for obj in objects:
            approach = obj["close_approach_data"][0] if obj["close_approach_data"] else None
            if not approach:
                continue

            diameter = obj["estimated_diameter"]["kilometers"]

            asteroids.append({
                "id": obj["id"],
                "name": obj["name"].strip("()"),
                "date": day,
                "diameter_km_min": round(diameter["estimated_diameter_min"], 4),
                "diameter_km_max": round(diameter["estimated_diameter_max"], 4),
                "velocity_kph": round(
                    float(approach["relative_velocity"]["kilometers_per_hour"]), 0
                ),
                "miss_distance_km": round(
                    float(approach["miss_distance"]["kilometers"]), 0
                ),
                "is_hazardous": obj["is_potentially_hazardous_asteroid"],
            })

    # Sort by date so the chart draws left-to-right chronologically.
    asteroids.sort(key=lambda a: a["date"])

    return jsonify(
        start_date=start.isoformat(),
        end_date=end.isoformat(),
        count=len(asteroids),
        asteroids=asteroids,
    )


if __name__ == "__main__":
    # debug=True is fine for local dev only - we'll make sure this is off
    # in production when we get to the Azure deployment phase.
    app.run(debug=True, port=5000)
