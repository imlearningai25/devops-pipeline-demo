// =============================================================================
// Jenkinsfile – Declarative Pipeline for devops-pipeline-demo
// =============================================================================
//
// WHAT IS A DECLARATIVE PIPELINE?
//   Jenkins supports two pipeline syntaxes: Scripted (Groovy) and Declarative.
//   Declarative is preferred for new pipelines because it's more readable and
//   has built-in validation. All logic lives inside a `pipeline { }` block.
//
// HOW TO USE THIS FILE:
//   1. In Jenkins: New Item → Pipeline → Pipeline script from SCM
//   2. Set SCM to Git, point to your repo
//   3. Jenkins automatically finds this Jenkinsfile and runs the pipeline
//
// PREREQUISITES IN JENKINS:
//   - Docker installed on the Jenkins agent (or use a Docker-in-Docker agent)
//   - kubectl configured with access to your Minikube cluster
//   - A Jenkins credential named 'DOCKER_CREDENTIALS_ID' (username/password)
//     stored at: Jenkins → Manage Jenkins → Credentials
// =============================================================================

pipeline {

    // -------------------------------------------------------------------------
    // AGENT
    // Which machine/container runs this pipeline.
    // 'any' = use any available Jenkins agent.
    // For real teams, specify a Docker agent or a labelled node.
    // -------------------------------------------------------------------------
    agent any

    // -------------------------------------------------------------------------
    // ENVIRONMENT VARIABLES
    // Defined once here, accessible in every stage as ${VAR_NAME}.
    // Change these to match your DockerHub username and setup.
    // -------------------------------------------------------------------------
    environment {
        // Your DockerHub username or private registry hostname
        REGISTRY        = "docker.io/nirajbjk"

        // The image name without the tag
        IMAGE_NAME      = "devops-demo"

        // Full image reference including the registry prefix
        // BUILD_NUMBER is a built-in Jenkins variable (e.g. "42")
        FULL_IMAGE      = "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"

        // Also tag as 'latest' for convenience
        LATEST_IMAGE    = "${REGISTRY}/${IMAGE_NAME}:latest"

        // Kubernetes namespace where the app is deployed (created in namespace.yaml)
        K8S_NAMESPACE   = "devops-demo"

        // Kubernetes deployment name (must match metadata.name in deployment.yaml)
        K8S_DEPLOYMENT  = "devops-demo-app"

        // Container name inside the pod spec (must match in deployment.yaml)
        K8S_CONTAINER   = "flask-app"

        // Jenkins credential ID for DockerHub (set up in Jenkins credential store)
        DOCKER_CREDS_ID = "DOCKER_CREDENTIALS_ID"

        // Where pytest writes its JUnit XML report (Jenkins parses this)
        TEST_REPORT     = "reports/test-results.xml"
    }

    // -------------------------------------------------------------------------
    // OPTIONS
    // Pipeline-level settings
    // -------------------------------------------------------------------------
    options {
        // Keep only the last 10 build logs (saves disk space)
        buildDiscarder(logRotator(numToKeepStr: "10"))

        // Fail the build if it runs longer than 20 minutes (prevent hung builds)
        timeout(time: 20, unit: "MINUTES")

        // Add timestamps to every log line (makes debugging much easier)
        timestamps()

        // Prevent two builds of the same branch running at the same time
        disableConcurrentBuilds()
    }

    // =========================================================================
    // STAGES – each stage runs sequentially; if one fails, later ones are skipped
    // =========================================================================
    stages {

        // ---------------------------------------------------------------------
        // STAGE 1: Checkout
        // Jenkins automatically checks out the repo when using "Pipeline from SCM",
        // but we add an explicit stage for visibility and to confirm the branch.
        // ---------------------------------------------------------------------
        stage("Checkout") {
            steps {
                echo "==> Checking out source code from branch: ${GIT_BRANCH}"

                // checkout scm uses the SCM configuration from the job definition.
                // This ensures we always build the correct branch/commit.
                checkout scm

                // Print the commit hash so we can correlate builds to commits
                sh "git log -1 --pretty='%h %s'"
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 2: Install Dependencies
        // Install Python packages needed for linting and tests.
        // In CI we install into the agent's Python environment (not a venv)
        // to keep things simple. Adjust for your agent setup.
        // ---------------------------------------------------------------------
        stage("Install Deps") {
            steps {
                echo "==> Installing Python dependencies"

                sh """

                    . venv/bin/activate



                    echo "Installed packages:"
                    pip list
                """
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 3: Lint
        // flake8 checks PEP 8 style and common Python errors.
        // A lint failure here catches simple bugs before running tests.
        //
        // --max-line-length 100  : slightly relaxed from the default 79
        // --exclude __pycache__  : skip generated files
        // ---------------------------------------------------------------------
        stage("Lint") {
            steps {
                echo "==> Running flake8 linter on app/"

                sh """
                    . venv/bin/activate
                    flake8 app/ \
                        --max-line-length=100 \
                        --exclude=__pycache__,*.pyc \
                        --statistics \
                        --count
                """

                echo "Lint passed!"
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 4: Unit Tests
        // Run pytest and output a JUnit XML report.
        // Jenkins reads the XML to show a test trend graph in the build UI.
        // ---------------------------------------------------------------------
        stage("Unit Tests") {
            steps {
                echo "==> Running pytest unit tests"

                // Create the reports directory if it doesn't exist
                sh "mkdir -p reports"



                sh """
                    . venv/bin/activate
                    pytest tests/ \
                        --junitxml=${TEST_REPORT} \
                        --tb=short \
                        -v
                """
            }

            post {
                // always: publish the test report even if tests fail
                // This lets us see WHICH tests failed in Jenkins UI
                always {
                    junit "${TEST_REPORT}"
                }
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 5: Build Docker Image
        // Builds the multi-stage Dockerfile and tags with BUILD_NUMBER + latest.
        // Using BUILD_NUMBER as the image tag gives us a unique, traceable tag
        // for every build – critical for rollbacks.
        // ---------------------------------------------------------------------
        stage("Build Image") {
            steps {
                echo "==> Building Docker image: ${FULL_IMAGE}"

                sh """
                    docker build \
                        --tag ${FULL_IMAGE} \
                        --tag ${LATEST_IMAGE} \
                        --label "git-commit=${GIT_COMMIT}" \
                        --label "build-number=${BUILD_NUMBER}" \
                        --label "build-date=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                        .
                """

                // Print the image size so we can track image bloat over time
                sh "docker image inspect ${FULL_IMAGE} --format='Image size: {{.Size}} bytes'"
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 6: Push Image
        // Authenticates with DockerHub using the stored Jenkins credential and
        // pushes both the versioned tag and the 'latest' tag.
        //
        // withCredentials: securely injects username/password without exposing
        // them in logs. Jenkins masks the values in console output.
        // ---------------------------------------------------------------------
        stage("Push Image") {
            steps {
                echo "==> Pushing image to registry: ${REGISTRY}"

                withCredentials([
                    usernamePassword(
                        credentialsId: "${DOCKER_CREDS_ID}",
                        usernameVariable: "DOCKER_USER",
                        passwordVariable: "DOCKER_PASS"
                    )
                ]) {
                    sh """
                        # Log in to Docker registry
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                        # Push versioned tag (e.g. yourusername/devops-demo:42)
                        docker push ${FULL_IMAGE}

                        # Push 'latest' tag so `docker pull devops-demo` always gets the newest build
                        docker push ${LATEST_IMAGE}

                        # Always log out after pushing to clean up credentials
                        docker logout
                    """
                }
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 7: Deploy to Kubernetes
        // Applies all Kubernetes manifests (idempotent – safe to re-run),
        // then updates the deployment to use the newly pushed image tag.
        //
        // kubectl set image: rolling-updates the deployment without downtime.
        // ---------------------------------------------------------------------
        stage("Deploy to K8s") {
            steps {
                echo "==> Deploying to Kubernetes namespace: ${K8S_NAMESPACE}"

                sh """
                    # Apply all manifests in the k8s/ directory.
                    # 'apply' is idempotent: creates resources that don't exist,
                    # updates ones that do. Safe to run on every deployment.
                    kubectl apply -f k8s/ --namespace=${K8S_NAMESPACE}

                    # Update the container image to the newly built tag.
                    # This triggers a rolling update: Kubernetes replaces pods
                    # one at a time, so there is zero downtime.
                    kubectl set image deployment/${K8S_DEPLOYMENT} \
                        ${K8S_CONTAINER}=${FULL_IMAGE} \
                        --namespace=${K8S_NAMESPACE}

                    # Wait for the rollout to complete before moving on.
                    # If the new pods crash, this command fails and the pipeline
                    # stops, preventing us from smoke-testing a broken deployment.
                    kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                        --namespace=${K8S_NAMESPACE} \
                        --timeout=120s
                """
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 8: Smoke Test
        // A quick sanity check: hit the /health endpoint of the newly deployed
        // service and verify it returns HTTP 200.
        // This catches deployment issues (wrong image, misconfigured env vars,
        // missing secrets) immediately after deploy.
        // ---------------------------------------------------------------------
        stage('Smoke Test') {
            steps {
                sh '''
                    # Get the NodePort directly via kubectl
                    NODE_PORT=$(kubectl get svc devops-demo-service \
                    --namespace=devops-demo \
                    -o jsonpath='{.spec.ports[0].nodePort}')

                    SERVICE_URL="http://192.168.49.2:${NODE_PORT}"
                    echo "Testing URL: ${SERVICE_URL}/health"

                    for i in 1 2 3 4 5; do
                        HTTP_CODE=$(curl --silent --output /dev/null \
                        --write-out "%{http_code}" \
                        --max-time 10 "${SERVICE_URL}/health")
                        if [ "$HTTP_CODE" = "200" ]; then
                            echo "Smoke test PASSED – HTTP 200"
                            exit 0
                        fi
                        echo "Attempt ${i}/5 – HTTP ${HTTP_CODE}, retrying in 5s..."
                        sleep 5
                    done

                    echo "Smoke test FAILED after 5 attempts"
                    exit 1
                '''
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 9: Notify
        // Print a clear success message. In a real team setup, replace the
        // echo statements with a Slack webhook call (see the comment below).
        // ---------------------------------------------------------------------
        stage("Notify") {
            steps {
                echo "==> Pipeline complete"
                echo "Image: ${FULL_IMAGE}"
                echo "Build: #${BUILD_NUMBER} | Branch: ${GIT_BRANCH} | Commit: ${GIT_COMMIT}"
                echo "SUCCESS: devops-demo version ${BUILD_NUMBER} deployed to ${K8S_NAMESPACE}"

                /* ── Optional: Slack notification ─────────────────────────────
                   1. Install the 'Slack Notification Plugin' in Jenkins
                   2. Add a Jenkins credential of type 'Secret text' with your
                      Slack webhook URL, ID = 'SLACK_WEBHOOK'
                   3. Uncomment the block below:

                withCredentials([string(credentialsId: 'SLACK_WEBHOOK', variable: 'SLACK_URL')]) {
                    sh """
                        curl -s -X POST \${SLACK_URL} \
                            -H 'Content-type: application/json' \
                            --data '{"text": "✅ Build #${BUILD_NUMBER} of devops-demo deployed successfully!"}'
                    """
                }
                ────────────────────────────────────────────────────────────── */
            }
        }

    } // end stages

    // =========================================================================
    // POST – actions that run AFTER all stages, regardless of outcome
    // =========================================================================
    post {

        // always: runs whether the build succeeds, fails, or is aborted
        always {
            echo "==> Post-build cleanup"

            // Remove the local Docker image to reclaim disk space on the agent.
            // '|| true' prevents this from failing the build if the image
            // was never created (e.g. build failed at 'Install Deps' stage).
            sh "docker rmi ${FULL_IMAGE} ${LATEST_IMAGE} || true"

            // Archive the test report XML as a build artefact so it can be
            // downloaded from the Jenkins build page
            archiveArtifacts artifacts: "reports/**", allowEmptyArchive: true
        }

        success {
            echo "BUILD SUCCEEDED – #${BUILD_NUMBER}"
            // Extend here: update a deployment tracker, create a Git tag, etc.
        }

        failure {
            echo "BUILD FAILED – #${BUILD_NUMBER}"
            echo "Check the console output above for details."
            // Extend here: send a failure alert, open a PagerDuty incident, etc.

            /* ── Optional: auto-rollback on failure ───────────────────────────
               If the smoke test failed, roll back to the previous deployment:

            sh """
                kubectl rollout undo deployment/${K8S_DEPLOYMENT} \
                    --namespace=${K8S_NAMESPACE} || true
            """
            ────────────────────────────────────────────────────────────── */
        }

        unstable {
            // 'unstable' means the build ran but tests failed (non-zero exit)
            echo "BUILD UNSTABLE – some tests failed. Check the test report."
        }

    } // end post

} // end pipeline
