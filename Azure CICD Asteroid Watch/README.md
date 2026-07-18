# Asteroid Watch
A Flask app that visualizes NASA's Near-Earth Object (NeoWs) data as an
interactive bubble chart — asteroids plotted by close-approach date and miss
distance, sized by estimated diameter, with potentially hazardous objects
flagged. Deployed to Azure via Terraform, with a GitHub Actions CI/CD
pipeline that tests, builds, and deploys the app automatically on every push.

**Live demo:** https://ca-asteroidwatch-dev.kindflower-2d9d966a.eastus.azurecontainerapps.io/

This project was built in four phases, each demonstrating a different layer
of the cloud/DevOps stack: the application itself, automated testing,
containerization, and infrastructure-as-code with a full CI/CD pipeline.

---

## Architecture

```
GitHub push (main branch, this project's folder only)
        │
        ▼
GitHub Actions workflow
  ├─ Job 1: test        → pytest (mocked NASA API calls)
  └─ Job 2: build-and-deploy (only runs if tests pass)
       ├─ Azure login via OIDC (no stored secrets)
       ├─ Build Docker image, tag with git commit SHA
       ├─ Push image to Azure Container Registry
       └─ terraform apply (state stored remotely in Azure Storage)
                │
                ▼
        Azure Container Apps environment
          ├─ Container App (the running Flask app, gunicorn)
          ├─ Managed Identity → AcrPull role on the registry
          └─ Log Analytics Workspace (container logs)
```

---

## Phase 1: The application

A Flask app with two routes: `/` serves the page, and `/api/asteroids`
proxies NASA's NeoWs feed endpoint server-side, reshaping the response into
something the frontend can chart directly with Chart.js.

**Key decision — the NASA API key never reaches the browser.** The Flask
backend is the only thing that calls NASA; the frontend only ever talks to
our own API. This is the same pattern used later for Azure secrets (Key
Vault / App Service configuration): credentials stay server-side.

A `/healthz` route was added early, trivial at the time, but it's exactly
what Azure Container Apps' health probes call to determine whether the app
is alive and ready for traffic.

## Phase 1.5: Automated tests

A `pytest` suite covering health checks, date-range validation (including
the boundary case — exactly 7 days should pass, 8 should fail), NASA
response parsing, and NASA-failure handling (mocked network errors → a
clean 502 instead of a crash).

**Key decision — tests never call the real NASA API.** `requests.get` is
mocked with fixed fake data, so the suite runs instantly, deterministically,
and without needing a real API key or network access. This matters because
these are the exact tests GitHub Actions runs on every push, before
anything gets built or deployed — they're the pipeline's gatekeeper.

## Phase 2: Containerization

A multi-stage-conscious `Dockerfile`: dependencies are installed in a layer
that's cached separately from the application code, so code-only changes
don't force a full dependency reinstall on every build. The app runs as a
non-root user inside the container (limits blast radius if a dependency is
ever compromised), and gunicorn replaces Flask's development server as the
actual production entrypoint.

**Key decision — secrets are never baked into the image.** The NASA API key
is injected at `docker run` / Container App deployment time via an
environment variable, never written into a layer. Image layers can persist
indefinitely even after files are "removed" in a later layer, so anything
baked in at build time should be treated as permanently exposed.

## Phase 3: Azure infrastructure via Terraform

Provisions everything the app needs to run in Azure:

| Resource | Purpose | AWS equivalent |
|---|---|---|
| Resource Group | Groups everything for lifecycle/cleanup | — |
| Azure Container Registry (Basic SKU) | Stores the Docker image | ECR |
| Log Analytics Workspace | Container logs | CloudWatch Logs |
| Container App Environment | The "cluster" Container Apps run inside | ECS Cluster (Fargate) |
| Container App | The running app, scale-to-zero enabled | ECS Service (Fargate) |
| User-Assigned Managed Identity | Lets the Container App pull from ACR with no stored credentials | IAM role / instance profile |

**Key decision — a user-assigned (not system-assigned) managed identity.**
A system-assigned identity doesn't exist until the Container App itself is
created, but the role assignment granting it registry access needs to exist
*before* the app tries to pull an image — a circular dependency. A
user-assigned identity has its own independent lifecycle, so it can be
granted access first, then attached to the app.

**Key decision — scale-to-zero.** `min_replicas = 0` means Azure stops
billing compute when nobody's using the app and spins a replica back up on
the next request (with a short cold-start delay). For a portfolio project
with sporadic traffic, this is the difference between paying for an
always-on instance and paying close to nothing most of the time.

## Phase 4: CI/CD pipeline

A GitHub Actions workflow that runs the test suite, builds and pushes the
Docker image (tagged with the git commit SHA, never `latest` — every deploy
references an exact, immutable image), and runs `terraform apply`, all
triggered by a push to `main`.

**Key decision — OIDC instead of a stored Azure credential.** GitHub issues
a short-lived identity token scoped to this exact repo and branch; Azure
verifies that token against a federated credential configured once, and
issues temporary access — no client secret sits in GitHub's secret store
waiting to be leaked or rotated.

**Key decision — remote Terraform state.** State lives in Azure Storage,
not on any one machine. GitHub Actions runners are ephemeral (a fresh,
empty environment on every run), so without remote state the pipeline would
have no memory of what already exists and would try to recreate everything
on every run.

---

## Debugging notes worth knowing about

Getting the pipeline's Azure authentication right surfaced a genuinely
non-obvious issue: Terraform's `azurerm` backend and provider both
auto-detect an active Azure CLI session and **prioritize it over explicit
OIDC configuration**, even when OIDC variables are set. Since the CLI
session in this pipeline belongs to a service principal (not a real user),
and CLI-based auth only supports user accounts, this caused a persistent
authentication failure that *looked* like a missing-credential problem but
wasn't. The fix required explicitly disabling CLI auth detection
(`use_cli = false` on the provider) and passing OIDC parameters directly as
`-backend-config` flags at `terraform init` time, since the backend and
provider don't share identical configuration surfaces.

Also worth noting: RBAC role assignments in Azure are eventually
consistent — a role granted moments ago can still return `403 Forbidden`
for a few minutes before propagation catches up, which is easy to mistake
for a permissions misconfiguration.

---

## Cost

This project is designed to run cheaply, but it isn't strictly free.
Actual Azure resource costs, at the time of writing:

| Resource | Approx. cost |
|---|---|
| Container App (scale-to-zero, low traffic) | Near $0 when idle; small compute charge per active second under load |
| Azure Container Registry (Basic SKU) | ~$0.167/day (~$5/month) flat, regardless of usage |
| Log Analytics Workspace | Free ingestion allowance, then billed per GB beyond it — negligible at this traffic volume |
| Storage Account (Terraform state) | Pennies/month — a few KB of state data |
| NASA API | Free |

The Container Registry's flat daily charge is the main fixed cost here —
Container Apps' scale-to-zero doesn't help with a registry that exists
whether or not it's being pulled from. **If this were purely a
learn-and-tear-down exercise**, `terraform destroy` between sessions avoids
any ongoing charge entirely, at the cost of losing the "always-live demo
link" for a resume.

## Tradeoffs and honest limitations

- **The NASA API key sits in Terraform state in plaintext.** State files
  aren't encrypted by default. Fine for a solo portfolio project; in a real
  team setting this would move to Azure Key Vault with the Container App
  referencing it directly, rather than passing the secret through Terraform
  variables at all.
- **Single environment.** There's no separate staging/production split —
  everything is `dev`. A production setup would parameterize this
  (`environment = "prod"`) and likely use separate state files or
  workspaces per environment.
- **ACR Basic SKU has no geo-replication or private networking.** Fine
  here; would need an upgrade for a multi-region or network-isolated setup.
- **Cold starts.** Scale-to-zero saves cost but means the first request
  after idle time is slower while a replica spins up. A latency-sensitive
  production app would set `min_replicas = 1` and eat the always-on cost
  instead.
- **The GitHub Actions service principal has `User Access Administrator`**
  scoped to the resource group, needed because Terraform manages the
  registry's role assignment. This is narrower than subscription-wide
  Owner, but it's still more privilege than a pipeline that *only* deployed
  application code (not IAM) would need.

## Project structure

```
app.py                  # Flask backend
templates/index.html    # Single-page frontend
static/                 # CSS and JS (Chart.js rendering)
tests/test_app.py       # pytest suite, NASA API mocked
Dockerfile               # Production image (gunicorn, non-root user)
.dockerignore
terraform/               # Azure infrastructure (Container Apps, ACR, etc.)
.github/workflows/       # CI/CD pipeline (at repo root, not here)
```

## Running it yourself

### Locally
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # add your free NASA API key from https://api.nasa.gov
set -a; source .env; set +a
python app.py
```
Open http://localhost:5000

### Tests
```bash
pip install -r requirements-dev.txt
pytest -v
```

### Docker
```bash
docker build -t asteroid-watch .
docker run -p 8000:8000 -e NASA_API_KEY=your_key_here asteroid-watch
```
Open http://localhost:8000

### Azure (manual, without the pipeline)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # add your NASA API key
terraform init
terraform apply
```

The GitHub Actions pipeline (`.github/workflows/asteroid-watch-deploy.yml`
at the repo root) handles all of the above automatically on every push to
`main` that touches this project's folder.
