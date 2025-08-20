pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 30, unit: 'MINUTES')
  }

  tools { maven 'Maven-3' }  // Configure under Manage Jenkins → Tools

  parameters {
    string(name: 'IMAGE_NAME', defaultValue: 'vs7098/hello-world-springboot', description: 'Registry repo')
    string(name: 'KUBE_NAMESPACE', defaultValue: 'default', description: 'K8s namespace')
    string(name: 'KUBE_CONTEXT', defaultValue: '', description: 'Optional kube context alias')
    booleanParam(name: 'PUSH_LATEST', defaultValue: true, description: 'Also push :latest')
  }

  environment {
    REGISTRY = 'docker.io'                       // set to your registry host if not Docker Hub
    TAG = "${env.BRANCH_NAME ?: 'local'}-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
        sh 'git rev-parse --short HEAD > .git/shortsha || true'
        script {
          env.GIT_SHA = readFile('.git/shortsha').trim()
          env.TAG = "${env.TAG}-${env.GIT_SHA}"
        }
        echo "Image tag → ${env.REGISTRY}/${params.IMAGE_NAME}:${env.TAG}"
      }
    }

    stage('Maven Build') {
      steps {
        sh '''
          mvn -B -DskipTests=true clean package
          ls -lh target || true
        '''
      }
    }

    stage('Docker Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-registry-creds',
                                          usernameVariable: 'DOCKER_USER',
                                          passwordVariable: 'DOCKER_PASS')]) {
          sh '''
            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin ${REGISTRY}
            docker build \
              --pull \
              --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
              --build-arg GIT_SHA=${GIT_SHA} \
              -t ${REGISTRY}/${IMAGE_NAME}:${TAG} .
            docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}
            if [ "${PUSH_LATEST}" = "true" ]; then
              docker tag ${REGISTRY}/${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:latest
              docker push ${REGISTRY}/${IMAGE_NAME}:latest
            fi
            docker logout ${REGISTRY} || true
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-cred', variable: 'KUBECONFIG_FILE')]) {
          sh '''
            set -e
            export KUBECONFIG="${KUBECONFIG_FILE}"
            if [ -n "${KUBE_CONTEXT}" ]; then
              kubectl config use-context "${KUBE_CONTEXT}"
            fi
            # Ensure namespace exists
            kubectl get ns ${KUBE_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${KUBE_NAMESPACE}

            # Apply manifests (uses image tag via kustomize-style envsubst)
            export IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
            envsubst < k8s/deployment.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f -
            kubectl -n ${KUBE_NAMESPACE} apply -f k8s/service.yaml

            # Wait for rollout
            APP_NAME=$(yq -r '.metadata.name' k8s/deployment.yaml 2>/dev/null || echo hello-world-springboot)
            kubectl -n ${KUBE_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=180s
          '''
        }
      }
    }
  }

  post {
    success {
      echo "✅ Deployed ${env.REGISTRY}/${params.IMAGE_NAME}:${env.TAG} to ${params.KUBE_NAMESPACE}"
    }
    failure {
      echo "❌ Pipeline failed — check stage logs."
    }
    always { cleanWs() }
  }
}
