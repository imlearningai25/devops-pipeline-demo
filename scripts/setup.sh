#!/usr/bin/env bash
# =============================================================================
# scripts/setup.sh
# ----------------
# One-shot setup script for the devops-pipeline-demo project.
#
# What this script does:
#   1. Checks that all prerequisite tools are installed
#   2. Starts Minikube with the Docker driver
#   3. Enables required Minikube addons
#   4. Applies all Kubernetes manifests
#   5. Starts the Prometheus + Grafana monitoring stack
#   6. Prints the access URLs for the app and Grafana
#
# USAGE:
#   chmod +x scripts/setup.sh
#   ./scripts/setup.sh
#
# =============================================================================

# ── Shell options ─────────────────────────────────────────────────────────────
set -e          # Exit immediately if any command returns a non-zero exit code
set -u          # Treat unset variables as errors
set -o pipefail # Fail if any command in a pipe fails (not just the last one)

# ── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'  # No colour (reset)

# ── Helper functions ─────────────────────────────────────────────────────────

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Prints a section banner so the script output is easy to read
banner() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $*${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Checks if a command exists on PATH; prints result and exits if missing
require_tool() {
    local tool="$1"
    local install_hint="${2:-"Please install ${tool} and retry."}"
    if command -v "${tool}" &>/dev/null; then
        success "${tool} found: $(${tool} --version 2>&1 | head -1)"
    else
        error "${tool} not found. ${install_hint}"
        exit 1
    fi
}

# ── Resolve project root (the directory containing this script's parent) ─────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${PROJECT_ROOT}/k8s"
MONITORING_DIR="${PROJECT_ROOT}/monitoring"
K8S_NAMESPACE="devops-demo"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Prerequisite checks
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 1 — Checking prerequisites"

require_tool "docker"   "Install Docker Desktop from https://www.docker.com/products/docker-desktop"
require_tool "kubectl"  "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
require_tool "minikube" "Install Minikube: https://minikube.sigs.k8s.io/docs/start/"
require_tool "python3"  "Install Python 3.11+: https://www.python.org/downloads/"

# Jenkins check is informational only – it may be running as a Docker container
if command -v jenkins &>/dev/null; then
    success "jenkins found"
else
    warn "jenkins not found on PATH. If you are running Jenkins via Docker, that is fine."
    warn "Jenkins Docker: docker run -p 8080:8080 jenkins/jenkins:lts"
fi

success "All required prerequisites are installed."


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Start Minikube
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 2 — Starting Minikube"

# Check if Minikube is already running to avoid re-starting it
MINIKUBE_STATUS="$(minikube status --format='{{.Host}}' 2>/dev/null || echo 'Stopped')"

if [[ "${MINIKUBE_STATUS}" == "Running" ]]; then
    success "Minikube is already running. Skipping start."
else
    info "Starting Minikube with Docker driver (this may take a minute)..."
    minikube start \
        --driver=docker \
        --cpus=2 \
        --memory=2048mb \
        --kubernetes-version=stable

    success "Minikube started."
fi

# Print Minikube IP for reference
MINIKUBE_IP="$(minikube ip)"
info "Minikube IP: ${MINIKUBE_IP}"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Enable Minikube addons
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 3 — Enabling Minikube addons"

# metrics-server: required for kubectl top and HPA CPU-based autoscaling
info "Enabling metrics-server addon..."
minikube addons enable metrics-server
success "metrics-server enabled."

# ingress: allows exposing services via an Ingress resource (optional for this demo)
info "Enabling ingress addon..."
minikube addons enable ingress
success "ingress enabled."

info "Current addons:"
minikube addons list | grep -E "metrics-server|ingress"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Apply Kubernetes manifests
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 4 — Deploying to Kubernetes"

# Apply manifests in a specific order:
#   1. namespace.yaml first – the namespace must exist before other resources
#   2. remaining manifests – Deployment, Service, HPA
info "Creating namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

info "Applying Deployment, Service, and HPA..."
kubectl apply -f "${K8S_DIR}/deployment.yaml"
kubectl apply -f "${K8S_DIR}/service.yaml"
kubectl apply -f "${K8S_DIR}/hpa.yaml"

# Wait for the Deployment to become ready
# This blocks until at least 1 replica is available (or timeout)
info "Waiting for deployment to become ready (timeout: 90s)..."
kubectl rollout status deployment/devops-demo-app \
    --namespace="${K8S_NAMESPACE}" \
    --timeout=90s

success "Kubernetes deployment is ready."

# Show pod status
info "Pod status:"
kubectl get pods -n "${K8S_NAMESPACE}"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Start monitoring stack
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 5 — Starting Prometheus + Grafana monitoring stack"

COMPOSE_FILE="${MONITORING_DIR}/docker-compose.monitoring.yml"

info "Starting containers in background..."
docker compose -f "${COMPOSE_FILE}" up -d

# Give Grafana a few seconds to finish provisioning before printing the URL
info "Waiting for Grafana to initialise (10s)..."
sleep 10

# Check containers are running
if docker compose -f "${COMPOSE_FILE}" ps | grep -q "running"; then
    success "Monitoring stack is running."
else
    warn "One or more monitoring containers may not be running. Check with:"
    warn "  docker compose -f monitoring/docker-compose.monitoring.yml ps"
fi


# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Print access URLs
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 6 — Access URLs"

# Get the NodePort service URL from Minikube
APP_URL="$(minikube service devops-demo-service \
    --namespace="${K8S_NAMESPACE}" \
    --url 2>/dev/null || echo "Run: minikube service devops-demo-service -n ${K8S_NAMESPACE} --url")"

echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  devops-pipeline-demo is ready!                             │${NC}"
echo -e "${BOLD}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${BOLD}│${NC}  Flask App:   ${GREEN}${APP_URL}${NC}"
echo -e "${BOLD}│${NC}  Health:      ${GREEN}${APP_URL}/health${NC}"
echo -e "${BOLD}│${NC}  Metrics:     ${GREEN}${APP_URL}/metrics${NC}"
echo -e "${BOLD}│${NC}  Prometheus:  ${GREEN}http://localhost:9090${NC}"
echo -e "${BOLD}│${NC}  Grafana:     ${GREEN}http://localhost:3000${NC}  (admin / admin)"
echo -e "${BOLD}│${NC}  Jenkins:     ${GREEN}http://localhost:8080${NC}  (if running locally)"
echo -e "${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Open Grafana and navigate to Dashboards → DevOps Demo → Flask App"
echo "  2. Trigger the Jenkins pipeline to build and deploy a new version"
echo "  3. Run scripts/teardown.sh when you are done"
echo ""
