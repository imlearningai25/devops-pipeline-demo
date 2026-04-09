"""
tests/test_app.py
-----------------
Pytest unit tests for the Flask microservice (app/main.py).

How to run locally:
  cd devops-pipeline-demo
  pip install -r app/requirements.txt pytest
  pytest tests/ -v --tb=short

In the Jenkins pipeline, pytest is invoked with:
  pytest tests/ --junitxml=reports/test-results.xml
so that Jenkins can parse and display the test report.
"""

import sys
import os

# ---------------------------------------------------------------------------
# Path fix – make sure Python can import 'app.main' when tests are run
# from the project root (as Jenkins does).
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

import pytest
from main import app  # import the Flask application object


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """
    Creates a Flask test client.

    Flask's test client lets us send fake HTTP requests without
    starting a real network server – fast and side-effect free.

    'TESTING = True' turns on Flask's exception propagation so test
    failures show the real traceback, not a generic 500 page.
    """
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client  # 'yield' means setup runs before the test, teardown after


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

class TestRootEndpoint:
    """Tests for GET /"""

    def test_root_returns_200(self, client):
        """The root endpoint must respond with HTTP 200 OK."""
        response = client.get("/")
        assert response.status_code == 200, (
            f"Expected 200, got {response.status_code}"
        )

    def test_root_returns_json(self, client):
        """The root endpoint must return a JSON content-type header."""
        response = client.get("/")
        assert response.content_type == "application/json"

    def test_root_payload_structure(self, client):
        """
        The root payload must contain 'status' and 'version' keys
        with the expected values.
        """
        response = client.get("/")
        data = response.get_json()

        assert data is not None, "Response body is not valid JSON"
        assert "status" in data, "Missing key: 'status'"
        assert "version" in data, "Missing key: 'version'"
        assert data["status"] == "running"
        assert data["version"] == "1.0.0"


class TestHealthEndpoint:
    """Tests for GET /health"""

    def test_health_returns_200(self, client):
        """The health endpoint must respond with HTTP 200 OK."""
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_returns_json(self, client):
        """The health endpoint must return a JSON content-type header."""
        response = client.get("/health")
        assert response.content_type == "application/json"

    def test_health_payload(self, client):
        """
        The health payload must contain {"health": "ok"}.
        Kubernetes liveness/readiness probes parse this response.
        """
        response = client.get("/health")
        data = response.get_json()

        assert data is not None, "Response body is not valid JSON"
        assert "health" in data, "Missing key: 'health'"
        assert data["health"] == "ok"


class TestMetricsEndpoint:
    """Tests for GET /metrics"""

    def test_metrics_returns_200(self, client):
        """
        The /metrics endpoint must be reachable (HTTP 200).
        Prometheus will scrape this endpoint; a non-200 response
        causes the scrape to fail and gaps appear in dashboards.
        """
        response = client.get("/metrics")
        assert response.status_code == 200

    def test_metrics_content_type(self, client):
        """
        Prometheus expects a specific MIME type from the metrics endpoint.
        The response must start with 'text/plain' (Prometheus text format).
        """
        response = client.get("/metrics")
        # prometheus_client uses 'text/plain; version=0.0.4; charset=utf-8'
        assert response.content_type.startswith("text/plain"), (
            f"Unexpected content type: {response.content_type}"
        )

    def test_metrics_body_contains_flask_metric(self, client):
        """
        After at least one request, the metrics body should contain
        the custom counter we defined (flask_request_count).

        We make a call to / first to ensure the counter is non-zero,
        then check the /metrics output.
        """
        # Trigger the counter by hitting the root endpoint
        client.get("/")

        response = client.get("/metrics")
        body = response.data.decode("utf-8")

        assert "flask_request_count" in body, (
            "Custom metric 'flask_request_count' not found in /metrics output"
        )
        assert "flask_request_latency_seconds" in body, (
            "Custom metric 'flask_request_latency_seconds' not found in /metrics output"
        )


class TestEdgeCases:
    """Additional edge-case tests."""

    def test_unknown_route_returns_404(self, client):
        """Requests to undefined routes must return HTTP 404."""
        response = client.get("/this-route-does-not-exist")
        assert response.status_code == 404

    def test_post_to_root_returns_405(self, client):
        """
        Only GET is defined on /. A POST should return 405 Method Not Allowed.
        This verifies we haven't accidentally opened up unwanted HTTP methods.
        """
        response = client.post("/")
        assert response.status_code == 405
