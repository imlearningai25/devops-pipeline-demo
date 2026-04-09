"""
app/main.py
-----------
Flask microservice for the devops-pipeline-demo project.

Exposes three routes:
  GET /        → basic status/version response
  GET /health  → liveness/readiness probe used by Kubernetes
  GET /metrics → Prometheus metrics endpoint (scraped every 15 s)

Instrumentation:
  - REQUEST_COUNT   : counter  – total HTTP requests, labelled by method+endpoint+status
  - REQUEST_LATENCY : histogram – request duration in seconds, labelled by endpoint
"""

import time
from flask import Flask, jsonify, request, Response
from prometheus_client import (
    Counter,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# ---------------------------------------------------------------------------
# App initialisation
# ---------------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Prometheus metric definitions
# ---------------------------------------------------------------------------

# Counts every HTTP request; labels let us slice by method, path, and status code
REQUEST_COUNT = Counter(
    "flask_request_count",
    "Total number of HTTP requests received",
    ["method", "endpoint", "http_status"],
)

# Tracks how long each request takes; buckets are in seconds
REQUEST_LATENCY = Histogram(
    "flask_request_latency_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)


# ---------------------------------------------------------------------------
# Middleware – record latency and count for every request automatically
# ---------------------------------------------------------------------------

@app.before_request
def _start_timer():
    """Store the request start time so we can compute elapsed time after."""
    request._start_time = time.time()


@app.after_request
def _record_metrics(response):
    """
    Called after every request. Calculates elapsed time and increments
    both the counter and the latency histogram.
    """
    elapsed = time.time() - request._start_time  # seconds

    REQUEST_LATENCY.labels(endpoint=request.path).observe(elapsed)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        http_status=str(response.status_code),
    ).inc()

    return response


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/", methods=["GET"])
def index():
    """
    Root endpoint.
    Returns a simple JSON payload confirming the service is alive
    and shows the current application version.
    """
    return jsonify({"status": "running", "version": "1.0.0"}), 200


@app.route("/health", methods=["GET"])
def health():
    """
    Health-check endpoint used by:
      - Kubernetes liveness  probe (is the app still running?)
      - Kubernetes readiness probe (is the app ready to serve traffic?)

    Returns HTTP 200 as long as the application process is alive.
    Extend this route to check DB connections, cache availability, etc.
    """
    return jsonify({"health": "ok"}), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    """
    Prometheus scrape endpoint.
    Returns metrics in the standard Prometheus text exposition format.
    Prometheus is configured (in monitoring/prometheus.yml) to call this
    every 15 seconds.
    """
    # generate_latest() serialises all registered metrics to bytes
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------------------
# Entry point (used when running locally with `python main.py`)
# In production/containers we use Gunicorn (see Dockerfile CMD).
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # debug=False is intentional – never run debug mode in containers
    app.run(host="0.0.0.0", port=5000, debug=False)
