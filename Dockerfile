# =============================================================================
# Dockerfile – Multi-Stage Build for devops-pipeline-demo Flask App
# =============================================================================
#
# WHY MULTI-STAGE?
#   Stage 1 (builder) installs all Python packages – this requires build tools
#   that bloat the image and create security surface area.
#   Stage 2 (runtime) copies ONLY the compiled packages, keeping the final
#   image small (~100 MB vs ~400 MB for a single-stage build).
#
# BUILD:
#   docker build -t devops-demo:latest .
#
# RUN LOCALLY:
#   docker run -p 5000:5000 devops-demo:latest
#   curl http://localhost:5000/health
# =============================================================================


# -----------------------------------------------------------------------------
# STAGE 1 — builder
# Purpose: install Python dependencies in an isolated layer
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Set a clean working directory for the build stage
WORKDIR /build

# Copy only the requirements file first.
# Docker caches layers – by copying requirements before source code,
# a `docker build` only re-runs pip install when requirements.txt changes,
# not on every source code change (speeds up CI significantly).
COPY app/requirements.txt .

# Install dependencies into a specific prefix directory (/install).
# --no-cache-dir  : don't cache the pip download cache (keeps image small)
# --prefix /install : installs packages to /install instead of the system
#                     Python so we can copy just this folder to the runtime stage
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# -----------------------------------------------------------------------------
# STAGE 2 — runtime
# Purpose: lean production image with only what's needed to run the app
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS runtime

# ---- Security: run as a non-root user ----------------------------------------
# Running as root inside a container is a security risk – if an attacker
# escapes the container, they land as root on the host.
# We create a dedicated system user 'appuser' with no home dir and no shell.
RUN adduser --disabled-password --no-create-home --gecos "" appuser

# Set working directory inside the container
WORKDIR /app

# Copy installed packages from the builder stage into the system Python path.
# /usr/local is the standard prefix for Python packages inside the slim image.
COPY --from=builder /install /usr/local

# Copy the application source code into /app
# We copy only the app/ directory – tests, scripts, etc. do NOT belong in prod
COPY app/ .

# Tell Docker (and humans) that the container listens on port 5000
# NOTE: EXPOSE is documentation only – you still need to publish (-p) at runtime
EXPOSE 5000

# Switch to the non-root user for all subsequent RUN/CMD/ENTRYPOINT instructions
USER appuser

# ---- Health check (optional but useful for `docker run` and docker-compose) --
# Docker will call this command every 30 s; if it fails 3 times the container
# is marked 'unhealthy'. Kubernetes has its own probes defined in deployment.yaml.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

# ---- Start the application ---------------------------------------------------
# Use Gunicorn (production WSGI server) instead of Flask's dev server.
#   --workers 2       : 2 worker processes (good for a CPU-light microservice)
#   --bind 0.0.0.0:5000 : listen on all interfaces inside the container
#   --timeout 60      : worker timeout in seconds
#   --access-logfile - : log access to stdout (important for container logging)
#   main:app          : the 'app' object in main.py
CMD ["gunicorn", \
     "--workers", "2", \
     "--bind", "0.0.0.0:5000", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "main:app"]
