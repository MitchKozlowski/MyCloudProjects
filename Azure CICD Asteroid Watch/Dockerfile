# --- Base image ---
# "slim" variants are much smaller than the default python image (fewer
# preinstalled OS packages), which means faster pulls/pushes to Azure
# Container Registry later, and a smaller attack surface.
FROM python:3.12-slim

# --- Working directory inside the container ---
# Everything from here on happens relative to /app inside the container's
# own filesystem - this has nothing to do with paths on your laptop.
WORKDIR /app

# --- Install dependencies FIRST, before copying the rest of the code ---
# This is a deliberate ordering, not an accident: Docker caches each layer.
# If only your app code changes (not requirements.txt), Docker can reuse
# the cached "pip install" layer instead of redownloading every package on
# every build. If we copied all the code first, ANY code change would
# invalidate the pip install cache too, making every build slow.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Now copy the actual application code ---
COPY app.py .
COPY templates/ templates/
COPY static/ static/

# --- Run as a non-root user ---
# By default, containers run as root, which is more privilege than this
# app needs. If something ever went wrong (a vulnerability in a dependency,
# for example), a non-root process is much more limited in what it can do
# to the host. This is a standard production hardening step.
RUN useradd --create-home appuser
USER appuser

# --- Document which port the app listens on ---
# This doesn't actually publish the port (that happens with `docker run -p`
# or, later, Azure's own config) - it's metadata for humans and tooling.
EXPOSE 8000

# --- Start the app with gunicorn, not Flask's built-in dev server ---
# Remember the "WARNING: This is a development server" message you saw
# earlier? gunicorn is the production-grade WSGI server that message was
# telling you to use instead. `-b 0.0.0.0:8000` binds to all network
# interfaces inside the container so traffic from outside the container
# can reach it (127.0.0.1 would only accept connections from inside the
# container itself).
CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:app"]
