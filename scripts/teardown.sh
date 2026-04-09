#!/usr/bin/env bash
# =============================================================================
# scripts/teardown.sh
# --------------------
# Cleanly removes all resources created by scripts/setup.sh.
#
# What this script does:
#   1. Deletes the devops-demo Kubernetes namespace (removes all K8s resources)
#   2. Stops and removes the Prometheus + Grafana Docker Compose stack
#   3. Optionally stops Minikube
#
# USAGE:
#   chmod +x scripts/teardown.sh
#   ./scripts/teardown.sh
#
#   Skip Minikube stop (keep cluster running):
#   KEEP_MINIKUBE=true ./scripts/teardown.sh
#
# =============================================================================

set -e
set -o pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

banner() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $*${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Resolve paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONITORING_DIR="${PROJECT_ROOT}/monitoring"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.monitoring.yml"
K8S_NAMESPACE="devops-demo"

# ── Read optional flags ───────────────────────────────────────────────────────
# Set KEEP_MINIKUBE=true to skip stopping Minikube
KEEP_MINIKUBE="${KEEP_MINIKUBE:-false}"

echo ""
echo -e "${BOLD}devops-pipeline-demo — Teardown${NC}"
echo "This will remove all demo resources. Press CTRL+C within 5 seconds to cancel."
echo ""
sleep 5


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Delete the Kubernetes namespace
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 1 — Removing Kubernetes resources"

# Check if the namespace exists before trying to delete it
if kubectl get namespace "${K8S_NAMESPACE}" &>/dev/null; then
    info "Deleting namespace '${K8S_NAMESPACE}' and ALL resources inside it..."

    # Deleting the namespace cascades: all Pods, Deployments, Services,
    # HPAs, and any other namespaced resources are removed automatically.
    kubectl delete namespace "${K8S_NAMESPACE}" --wait=true

    success "Namespace '${K8S_NAMESPACE}' deleted."
else
    warn "Namespace '${K8S_NAMESPACE}' does not exist. Skipping."
fi


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Stop the monitoring Docker Compose stack
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 2 — Stopping monitoring stack (Prometheus + Grafana)"

if [[ -f "${COMPOSE_FILE}" ]]; then
    info "Stopping and removing Docker Compose containers, networks..."

    # 'down -v' removes containers, networks, AND named volumes.
    # Use 'down' (without -v) if you want to KEEP Prometheus/Grafana data.
    docker compose -f "${COMPOSE_FILE}" down -v

    success "Monitoring stack stopped and volumes removed."
else
    warn "Compose file not found at ${COMPOSE_FILE}. Skipping."
fi


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Optionally stop Minikube
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 3 — Minikube"

if [[ "${KEEP_MINIKUBE}" == "true" ]]; then
    info "KEEP_MINIKUBE=true – leaving Minikube running."
    info "The devops-demo namespace has been removed but the cluster is still up."
else
    # Ask the user interactively (skip if running non-interactively, e.g. in CI)
    if [[ -t 0 ]]; then
        echo ""
        read -r -p "$(echo -e "${YELLOW}Stop Minikube cluster? This deletes the entire local cluster. [y/N]:${NC} ")" STOP_MINIKUBE
    else
        # Non-interactive (e.g. called from another script): default to NO
        STOP_MINIKUBE="n"
    fi

    if [[ "${STOP_MINIKUBE}" =~ ^[Yy]$ ]]; then
        info "Stopping Minikube..."
        minikube stop
        success "Minikube stopped."

        echo ""
        read -r -p "$(echo -e "${YELLOW}Also DELETE the Minikube cluster (removes VM/disk)? [y/N]:${NC} ")" DELETE_MINIKUBE
        if [[ "${DELETE_MINIKUBE}" =~ ^[Yy]$ ]]; then
            info "Deleting Minikube cluster..."
            minikube delete
            success "Minikube cluster deleted."
        fi
    else
        info "Minikube left running. The devops-demo namespace has already been removed."
        info "To stop Minikube later: minikube stop"
        info "To delete Minikube later: minikube delete"
    fi
fi


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Clean up local Docker images (optional)
# ─────────────────────────────────────────────────────────────────────────────
banner "STEP 4 — Cleaning up local Docker images"

# Remove all locally cached devops-demo images to reclaim disk space.
# '|| true' prevents the script from failing if no images match the filter.
info "Removing local devops-demo Docker images..."
docker images --filter "reference=*devops-demo*" --format "{{.ID}}" \
    | xargs -r docker rmi --force 2>/dev/null \
    || true

success "Local images cleaned up (if any existed)."


# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Teardown complete                                          │${NC}"
echo -e "${BOLD}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${BOLD}│${NC}  ✓ Kubernetes namespace '${K8S_NAMESPACE}' removed"
echo -e "${BOLD}│${NC}  ✓ Prometheus + Grafana containers stopped"
echo -e "${BOLD}│${NC}  ✓ Docker images cleaned up"
echo -e "${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo "To re-run the demo: ./scripts/setup.sh"
echo ""
