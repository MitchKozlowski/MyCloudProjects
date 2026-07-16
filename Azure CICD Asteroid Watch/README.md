# Asteroid Watch

A small Flask app that visualizes NASA's Near Earth Object (NeoWs) data as an
interactive bubble chart — asteroids plotted by close-approach date and miss
distance, sized by estimated diameter, with potentially hazardous objects
flagged.

This is Phase 1 of a larger project: the app itself, built and run locally.
Later phases add automated testing, containerization, and a CI/CD pipeline
that deploys it to Azure using Terraform and GitHub Actions.

## Run it locally

```bash
python3 -m venv venv
source venv/bin/activate        # on Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env
# edit .env and add your free NASA API key from https://api.nasa.gov
# (or leave it as DEMO_KEY to try it out immediately, rate-limited)

export $(cat .env | xargs)      # loads NASA_API_KEY into your shell
python app.py
```

Then open http://localhost:5000

## Running the tests

```bash
pip install -r requirements-dev.txt
pytest -v
```

The tests never call the real NASA API — `app.requests.get` is mocked with
fake data, so the suite runs instantly and doesn't need your API key or a
network connection. This is what your GitHub Actions pipeline will run
automatically on every push, before anything gets deployed.

## How it works

- `app.py` — Flask backend. Serves the page and one JSON API route
  (`/api/asteroids`) that calls NASA's feed endpoint server-side and returns
  a simplified payload.
- `templates/index.html` — the single page.
- `static/js/app.js` — fetches from our own API and renders the chart with
  Chart.js.
- `static/css/style.css` — styling.

The NASA API key never reaches the browser — the Flask backend is the only
thing that talks to NASA. This mirrors how secrets will be handled in Azure
later (App Service configuration / Key Vault instead of a `.env` file).
