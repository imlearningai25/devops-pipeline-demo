# devops-pipeline-demo

A complete, beginner-friendly DevOps project that demonstrates a full CI/CD lifecycle using real-world tools. Follow the quick-start below and you will have a running Flask microservice, automated Jenkins pipeline, Kubernetes deployment, and live Grafana monitoring dashboard — all on your laptop.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Quick Start (5 steps)](#quick-start)
5. [Pipeline Stages Explained](#pipeline-stages-explained)
6. [Monitoring](#monitoring)
7. [Troubleshooting](#troubleshooting)
8. [Branching Strategy](#branching-strategy)
9. [Cleanup](#cleanup)

---

## Prerequisites

Install the following tools before running the demo. Links to official install pages are provided.

| Tool | Min. Version | Install Link |
|---|---|---|
| **Docker Desktop** | 24.x | https://www.docker.com/products/docker-desktop |
| **Minikube** | 1.32+ | https://minikube.sigs.k8s.io/docs/start/ |
| **kubectl** | 1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| **Python** | 3.11+ | https://www.python.org/downloads/ |
| **Jenkins** | 2.440+ | https://www.jenkins.io/doc/book/installing/ or run via Docker (see below) |

### Quick Jenkins setup via Docker (simplest option)

```bash
docker run -d \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins-data:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts-jdk17
```

Access Jenkins at http://localhost:8080 and complete the initial setup wizard.

---

## Python/Docker installation inside Jinkins
# Exec into your Jenkins container
docker exec -it -u root <jenkins-container-name> bash

# Install Python + pip
apt-get update && apt-get install -y python3 python3-pip
ln -s /usr/bin/pip3 /usr/bin/pip
ln -s /usr/bin/python3 /usr/bin/python

# Install Docker CLI
apt-get update && apt-get install -y docker.io



## Architecture

```
  Developer Workflow
  ──────────────────

  ┌──────────┐    git push     ┌─────────────────────────────────────────────┐
  │  Laptop  │ ─────────────▶  │                  Jenkins                    │
  │ (VS Code)│                 │                                             │
  └──────────┘                 │  Checkout → Lint → Test → Build → Push      │
                               │                   │                         │
                               └───────────────────┼─────────────────────────┘
                                                   │
                                             docker push
                                                   │
                                                   ▼
                               ┌───────────────────────────────┐
                               │        Docker Registry        │
                               │   (DockerHub / private reg)   │
                               └───────────────┬───────────────┘
                                               │
                                         kubectl apply
                                               │
                                               ▼
                               ┌───────────────────────────────┐
                               │         Minikube / K8s        │
                               │                               │
                               │  ┌─────────┐  ┌─────────┐    │
                               │  │ Pod 1   │  │ Pod 2   │    │
                               │  │ Flask   │  │ Flask   │    │
                               │  └────┬────┘  └────┬────┘    │
                               │       └──────┬──────┘         │
                               │          Service               │
                               │        (NodePort)             │
                               └───────────────┬───────────────┘
                                               │
                                          /metrics
                                               │
                                               ▼
                               ┌───────────────────────────────┐
                               │     Prometheus (scrape)       │
                               │            +                  │
                               │     Grafana  (visualise)      │
                               │    localhost:3000             │
                               └───────────────────────────────┘
```

---

## Project Structure

```
devops-pipeline-demo/
│
├── app/
│   ├── main.py                  # Flask app: /, /health, /metrics endpoints
│   └── requirements.txt         # Python runtime dependencies
│
├── tests/
│   ├── __init__.py
│   └── test_app.py              # pytest unit tests (5 test cases)
│
├── k8s/
│   ├── namespace.yaml           # devops-demo namespace
│   ├── deployment.yaml          # 2-replica Flask deployment + probes
│   ├── service.yaml             # NodePort service (port 30080)
│   └── hpa.yaml                 # HPA: 2–5 replicas, 60% CPU target
│
├── monitoring/
│   ├── prometheus.yml           # Prometheus scrape config (15 s interval)
│   ├── grafana-dashboard.json   # Pre-built Grafana dashboard (3 panels)
│   ├── docker-compose.monitoring.yml  # Prometheus + Grafana stack
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml   # Auto-adds Prometheus data source to Grafana
│       └── dashboards/
│           └── default.yml      # Tells Grafana where to find dashboard JSON
│
├── scripts/
│   ├── setup.sh                 # Full environment setup in one command
│   └── teardown.sh              # Clean removal of all demo resources
│
├── Dockerfile                   # Multi-stage build (builder + runtime)
├── .dockerignore                # Excludes tests/docs from build context
├── Jenkinsfile                  # 9-stage declarative pipeline
└── README.md                    # This file
```

---

## Quick Start

### Step 1 — Clone the repository

```bash
git clone https://github.com/yourusername/devops-pipeline-demo.git
cd devops-pipeline-demo
```

### Step 2 — Run the automated setup script

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This single command will:
- Verify all prerequisites
- Start Minikube with 2 CPUs and 2 GB RAM
- Enable `metrics-server` and `ingress` addons
- Deploy the app to Kubernetes
- Start Prometheus and Grafana via Docker Compose

Expected duration: ~3 minutes on first run.

### Step 3 — Access the application

```bash
# Get the Minikube service URL
minikube service devops-demo-service -n devops-demo --url
```

Open the printed URL in your browser, or use curl:

```bash
APP_URL=$(minikube service devops-demo-service -n devops-demo --url)
curl $APP_URL/           # {"status":"running","version":"1.0.0"}
curl $APP_URL/health     # {"health":"ok"}
curl $APP_URL/metrics    # Prometheus text format
```

### Step 4 — Open Grafana

Navigate to http://localhost:3000 and log in with `admin` / `admin`.

Go to **Dashboards → DevOps Demo → DevOps Pipeline Demo – Flask App**.

You will see three live panels: Request Rate, Latency p95, and Pod CPU Usage.

### Step 5 — Trigger the Jenkins pipeline

1. Open Jenkins at http://localhost:8080
2. Create a new **Pipeline** job
3. Under *Pipeline*, choose **Pipeline script from SCM**
4. Set SCM to **Git**, enter the repo URL
5. Make sure the **Jenkinsfile** path is set to `Jenkinsfile`
6. Before running: add a DockerHub credential in Jenkins (ID: `DOCKER_CREDENTIALS_ID`) and update `REGISTRY` in the Jenkinsfile to your DockerHub username
7. Click **Build Now** and watch all 9 stages run

---

## Pipeline Stages Explained

| Stage | What it does |
|---|---|
| **1. Checkout** | Clones the repository from the configured SCM branch (`main`). Prints the commit hash for traceability. |
| **2. Install Deps** | Upgrades pip and installs `app/requirements.txt` plus `pytest` and `flake8` on the Jenkins agent. |
| **3. Lint** | Runs `flake8` on `app/` with a 100-character line limit. Catches syntax errors and style violations before wasting time on a build. |
| **4. Unit Tests** | Executes the pytest suite and writes a JUnit XML report to `reports/test-results.xml`. Jenkins parses this to display a test trend graph. |
| **5. Build Image** | Runs `docker build` using the multi-stage Dockerfile. Tags the image with `BUILD_NUMBER` (versioned) and `latest`. |
| **6. Push Image** | Authenticates with DockerHub using the stored credential and pushes both tags. Logs out immediately after. |
| **7. Deploy to K8s** | Applies all `k8s/` manifests with `kubectl apply`, then updates the deployment image tag with `kubectl set image`. Waits for the rollout to finish. |
| **8. Smoke Test** | Curls `/health` on the newly deployed service. Retries up to 5 times with a 5-second delay. Fails the build if the endpoint doesn't return HTTP 200. |
| **9. Notify** | Prints a build summary. Extend with a Slack webhook by uncommenting the section in the Jenkinsfile's `Notify` stage. |

---

## Monitoring

### What each Grafana panel shows

**Panel 1 – Request Rate (req/sec)**

Uses the PromQL expression:
```
sum(rate(flask_request_count_total[2m])) by (endpoint)
```
Shows how many HTTP requests per second the Flask app is handling, split by endpoint (`/`, `/health`, `/metrics`). A sudden drop to zero indicates the app has gone down.

**Panel 2 – Request Latency p50 / p95**

Uses `histogram_quantile()` to compute percentiles from the histogram bucket data:
```
histogram_quantile(0.95, sum(rate(flask_request_latency_seconds_bucket[2m])) by (le, endpoint))
```
p95 means 95% of requests complete within this time. A rising p95 is an early warning of performance degradation even when the average looks fine.

**Panel 3 – Pod CPU Usage**

```
sum(rate(container_cpu_usage_seconds_total{namespace="devops-demo"}[2m])) by (pod)
```
Shows CPU consumption per pod. When this approaches the `requests.cpu` value (`100m`), the HPA will start adding replicas.

### Importing the dashboard manually

If auto-provisioning doesn't work:

1. Log in to Grafana at http://localhost:3000
2. Go to **Dashboards → Import**
3. Click **Upload JSON file**
4. Select `monitoring/grafana-dashboard.json`
5. Choose **Prometheus** as the data source and click **Import**

### Generating test traffic

To see the panels light up with real data:

```bash
APP_URL=$(minikube service devops-demo-service -n devops-demo --url)

# Send 200 requests in a loop
for i in $(seq 1 200); do
  curl -s "$APP_URL/" > /dev/null
  curl -s "$APP_URL/health" > /dev/null
done
```

---

## Troubleshooting

### 1. ImagePullBackOff — pod can't pull the Docker image

**Symptom:** `kubectl get pods -n devops-demo` shows `ImagePullBackOff` or `ErrImagePull`.

**Cause:** The image name in `k8s/deployment.yaml` contains a placeholder (`yourdockerhubusername`), or the image hasn't been pushed yet.

**Fix:**
```bash
# Check the actual error
kubectl describe pod <pod-name> -n devops-demo | grep -A5 "Events:"

# Update the image to something that exists, e.g. a public test image
kubectl set image deployment/devops-demo-app \
  flask-app=docker.io/yourusername/devops-demo:latest \
  -n devops-demo

# Or build and load the image directly into Minikube (skips the registry)
eval $(minikube docker-env)       # Point Docker to Minikube's daemon
docker build -t devops-demo:local .
kubectl set image deployment/devops-demo-app \
  flask-app=devops-demo:local -n devops-demo
kubectl patch deployment devops-demo-app -n devops-demo \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"flask-app","imagePullPolicy":"Never"}]}}}}'
```

### 2. Minikube fails to start — port conflict or driver error

**Symptom:** `minikube start` fails with a port binding error or driver not found.

**Fix:**
```bash
# Check what's using port 8443 (Kubernetes API server port)
lsof -i :8443

# Try a different driver
minikube start --driver=virtualbox   # or --driver=hyperkit on macOS

# If the cluster is in a bad state, delete and recreate
minikube delete
minikube start --driver=docker
```

### 3. Grafana shows "No data" on all panels

**Symptom:** Panels are empty even though the app is running.

**Cause:** Prometheus can't reach the Flask app's `/metrics` endpoint.

**Fix:**
```bash
# 1. Check if Prometheus is scraping successfully
# Open http://localhost:9090/targets
# Look for the 'flask-app-local' job — Status should be "UP"

# 2. Verify the target URL in prometheus.yml is reachable FROM the Prometheus container
docker exec devops-prometheus \
  wget -qO- http://host.docker.internal:5000/metrics | head -20

# 3. If using Kubernetes NodePort, update prometheus.yml target to the Minikube IP
minikube service devops-demo-service -n devops-demo --url
# Then update the 'flask-app-k8s' job target in monitoring/prometheus.yml
# and reload: curl -X POST http://localhost:9090/-/reload
```

### 4. Jenkins pipeline fails at "Deploy to K8s" — kubectl not found or no cluster access

**Symptom:** Stage 7 fails with `kubectl: command not found` or `connection refused`.

**Fix:**
```bash
# If running Jenkins in Docker, ensure kubectl is installed in the container
# and that it has access to the Minikube kubeconfig:
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -v jenkins-data:/var/jenkins_home \
  -v ~/.kube:/var/jenkins_home/.kube:ro \      # Share kubeconfig
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts-jdk17

# Then install kubectl inside the running Jenkins container:
docker exec -u root jenkins \
  bash -c "curl -LO https://dl.k8s.io/release/\$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && install kubectl /usr/local/bin/"
```

### 5. HPA shows `<unknown>` for CPU metrics

**Symptom:** `kubectl get hpa -n devops-demo` shows `<unknown>/60%` in the TARGETS column.

**Cause:** The `metrics-server` addon isn't running or hasn't warmed up yet.

**Fix:**
```bash
# Verify metrics-server is enabled
minikube addons list | grep metrics-server

# Enable it if not already
minikube addons enable metrics-server

# Wait ~60 seconds for metrics to populate, then check
kubectl top pods -n devops-demo
kubectl get hpa -n devops-demo

# If metrics-server pods are crashing, check logs
kubectl logs -n kube-system -l k8s-app=metrics-server
```

---

## Branching Strategy

This project uses a simplified **GitHub Flow**:

```
main          ←── always deployable; Jenkins runs on every push
  └── feature/your-feature   ←── short-lived feature branches
  └── hotfix/urgent-fix       ←── emergency fixes off main
```

Rules:
- Never commit directly to `main`
- Open a pull request; require at least one approval
- Jenkins runs the full pipeline on every PR; merge is blocked on pipeline failure
- After merge, Jenkins deploys `main` automatically to the K8s cluster

---

## Cleanup

When you are done with the demo, run the teardown script:

```bash
./scripts/teardown.sh
```

This removes:
- The `devops-demo` Kubernetes namespace (and all pods/services inside it)
- The Prometheus and Grafana Docker containers and volumes
- Local Docker images for `devops-demo`

You will be asked whether to also stop/delete the Minikube cluster.

To keep Minikube running (e.g. you have other projects using it):

```bash
KEEP_MINIKUBE=true ./scripts/teardown.sh
```
