pipeline {
  agent { label 'kubernetes-builder' }
  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 90, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  parameters {
    booleanParam(name: 'DEPLOY_STAGING', defaultValue: false, description: 'Deploy the immutable image to the configured staging cluster')
    booleanParam(name: 'DEPLOY_PRODUCTION', defaultValue: false, description: 'Request the protected production deployment gate')
    string(name: 'IMAGE_REPOSITORY', defaultValue: 'registry.example.invalid/reliableapp-operator', description: 'Approved container registry repository, without a tag')
    choice(name: 'PERFORMANCE_GATE', choices: ['report-only', 'enforce', 'disabled'], description: 'Run the versioned Taurus performance comparison')
  }
  environment {
    IMAGE_REPOSITORY = "${params.IMAGE_REPOSITORY}"
    KIND_CLUSTER = 'reliableapp-operator-jenkins'
    RELEASE_NAME = 'reliableapp-operator'
    STAGING_NAMESPACE = 'reliableapp-staging'
    PRODUCTION_NAMESPACE = 'reliableapp-production'
    HELM_CHART = 'dist/chart'
    EVIDENCE_DIR = 'evidence'
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          if (params.DEPLOY_PRODUCTION && !params.DEPLOY_STAGING) {
            error('DEPLOY_PRODUCTION requires DEPLOY_STAGING so the same certified digest passes staging gates first')
          }
          env.GIT_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = env.GIT_COMMIT
          env.IMAGE = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
        }
      }
    }
    stage('Tool and source validation') {
      steps {
        sh 'bash ci/validate-tools.sh'
        sh 'make lint'
        sh 'make test'
        sh 'bash ci/race-test.sh'
      }
    }
    stage('Manifest and Helm validation') {
      steps {
        sh 'bash ci/validate-manifests.sh'
        sh 'helm lint "$HELM_CHART"'
        sh 'bash ci/validate-health-probes.sh "$HELM_CHART"'
        sh 'mkdir -p "$EVIDENCE_DIR" && helm template "$RELEASE_NAME" "$HELM_CHART" --set-string manager.image.repository="$IMAGE_REPOSITORY" --set-string manager.image.tag="$IMAGE_TAG" > "$EVIDENCE_DIR/helm-template.yaml"'
        archiveArtifacts artifacts: 'evidence/helm-template.yaml', fingerprint: true
      }
    }
    stage('Build immutable image') {
      steps {
        sh 'docker build --label "org.opencontainers.image.revision=$GIT_COMMIT" --label "org.opencontainers.image.source=${GIT_URL:-local}" -t "$IMAGE" .'
      }
    }
    stage('Image, SBOM, and vulnerability scan') {
      steps {
        sh 'bash ci/image-security.sh "$IMAGE" "$GIT_COMMIT"'
        archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: false, fingerprint: true
      }
    }
    stage('Kind E2E') {
      steps { sh 'bash ci/kind-e2e.sh "$KIND_CLUSTER" "$IMAGE"' }
      post {
        always {
          archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: true, fingerprint: true
        }
      }
    }
    stage('Publish immutable image') {
      when { expression { params.DEPLOY_STAGING } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'reliableapp-container-registry', usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD')]) {
          sh 'REGISTRY_USERNAME="$REGISTRY_USERNAME" REGISTRY_PASSWORD="$REGISTRY_PASSWORD" bash ci/publish-image.sh "$IMAGE" "$GIT_COMMIT"'
        }
        script {
          env.DEPLOY_IMAGE = readFile(file: 'evidence/published-image.txt').trim()
          echo "Promoting immutable image ${env.DEPLOY_IMAGE}"
        }
        archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: false, fingerprint: true
      }
    }
    stage('Staging candidate deployment') {
      when { expression { params.DEPLOY_STAGING } }
      steps {
        withCredentials([file(credentialsId: 'reliableapp-staging-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
          sh 'KUBECONFIG="$KUBECONFIG_FILE" bash ci/deploy.sh staging "$RELEASE_NAME" "$STAGING_NAMESPACE" "$DEPLOY_IMAGE" "$HELM_CHART"'
        }
        sh 'bash ci/performance-gate.sh "$PERFORMANCE_GATE"'
        withCredentials([string(credentialsId: 'reliableapp-prometheus-token', variable: 'PROMETHEUS_BEARER_TOKEN')]) {
          sh 'bash ci/slo-gate.sh staging'
          sh 'bash ci/shadow-traffic-gate.sh'
        }
      }
      post {
        failure {
          withCredentials([file(credentialsId: 'reliableapp-staging-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
            sh 'KUBECONFIG="$KUBECONFIG_FILE" bash ci/diagnostics.sh staging "$RELEASE_NAME" "$STAGING_NAMESPACE" || true'
          }
          archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: true, fingerprint: true
        }
      }
    }
    stage('Production approval') {
      when { expression { params.DEPLOY_PRODUCTION && params.DEPLOY_STAGING } }
      steps {
        input message: "Deploy ${env.DEPLOY_IMAGE} to production?", ok: 'Approve production deployment', submitter: 'reliableapp-production-approvers'
      }
    }
    stage('Production deployment') {
      when { expression { params.DEPLOY_PRODUCTION && params.DEPLOY_STAGING } }
      steps {
        lock(resource: 'reliableapp-production-deployments', inversePrecedence: true) {
          withCredentials([file(credentialsId: 'reliableapp-production-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
            script {
              // Capture the current Helm revision before deployment for potential rollback
              env.PRE_DEPLOYMENT_REVISION = sh(
                script: 'KUBECONFIG="$KUBECONFIG_FILE" helm history "$RELEASE_NAME" --namespace "$PRODUCTION_NAMESPACE" -o json 2>/dev/null | jq -r ".[-1].revision // 0" || echo "0"',
                returnStdout: true
              ).trim()
              echo "Pre-deployment Helm revision: ${env.PRE_DEPLOYMENT_REVISION}"
            }
            sh 'KUBECONFIG="$KUBECONFIG_FILE" bash ci/deploy.sh production "$RELEASE_NAME" "$PRODUCTION_NAMESPACE" "$DEPLOY_IMAGE" "$HELM_CHART"'
            echo "Production deployment completed successfully"
          }
        }
      }
      post {
        failure {
          withCredentials([file(credentialsId: 'reliableapp-production-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
            sh 'KUBECONFIG="$KUBECONFIG_FILE" bash ci/diagnostics.sh production "$RELEASE_NAME" "$PRODUCTION_NAMESPACE" || true'
          }
          archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: true, fingerprint: true
        }
      }
    }
    stage('Post-deployment SLO verification') {
      when { expression { params.DEPLOY_PRODUCTION && params.DEPLOY_STAGING } }
      steps {
        withCredentials([string(credentialsId: 'reliableapp-prometheus-token', variable: 'PROMETHEUS_BEARER_TOKEN')]) {
          sh 'bash ci/slo-gate.sh production'
        }
      }
      post {
        failure {
          script {
            echo "Post-deployment SLO verification failed. Initiating automatic rollback..."
            if (env.PRE_DEPLOYMENT_REVISION != null && env.PRE_DEPLOYMENT_REVISION != '0') {
              withCredentials([file(credentialsId: 'reliableapp-production-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                sh '''
                  KUBECONFIG="$KUBECONFIG_FILE" bash ci/rollback.sh "$RELEASE_NAME" "${PRE_DEPLOYMENT_REVISION}" "$PRODUCTION_NAMESPACE" || {
                    echo "Rollback failed; manual intervention required" >&2
                    exit 1
                  }
                  echo "Automatic rollback to revision ${PRE_DEPLOYMENT_REVISION} completed"
                '''
              }
            } else {
              echo "Warning: No previous revision available for rollback. Manual intervention required." >&2
            }
          }
          withCredentials([file(credentialsId: 'reliableapp-production-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
            sh 'KUBECONFIG="$KUBECONFIG_FILE" bash ci/diagnostics.sh production "$RELEASE_NAME" "$PRODUCTION_NAMESPACE" || true'
          }
          archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: true, fingerprint: true
        }
      }
    }
  }
}
