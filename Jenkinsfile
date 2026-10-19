// ============================================================
//  Qualibytes GPT — Jenkins Declarative Pipeline
//  Stages: Checkout → Build → Push → Deploy → Health Check
//
//  Needs (see README §7):
//    Credentials : dockerhub-credentials, app-server-ssh-key
//    Global env  : DOCKER_USERNAME, APP_SERVER_IP
//
//  All shell steps use single quotes ('''), so secrets are expanded by
//  the shell from env vars, never interpolated by Groovy into the
//  command text or the build log.
// ============================================================
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        DOCKER_CREDS          = credentials('dockerhub-credentials')
        DOCKER_IMAGE_FRONTEND = "${env.DOCKER_USERNAME}/qualibytes-frontend"
        DOCKER_IMAGE_BACKEND  = "${env.DOCKER_USERNAME}/qualibytes-backend"
        IMAGE_TAG             = "${env.BUILD_NUMBER}"
        APP_DIR               = 'qualibytes-gpt'
        SSH_OPTS              = '-o StrictHostKeyChecking=accept-new'
    }

    stages {

        // ── STAGE 1 ──────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Qualibytes GPT — Build #${env.BUILD_NUMBER}"
                checkout scm
                sh 'ls -la'
            }
        }

        // ── STAGE 2 ──────────────────────────────────────
        stage('Build Docker Images') {
            steps {
                sh '''
                    docker build -t "$DOCKER_IMAGE_FRONTEND:$IMAGE_TAG" -t "$DOCKER_IMAGE_FRONTEND:latest" ./frontend
                    docker build -t "$DOCKER_IMAGE_BACKEND:$IMAGE_TAG"  -t "$DOCKER_IMAGE_BACKEND:latest"  ./backend
                    docker images | grep qualibytes
                '''
            }
        }

        // ── STAGE 3 ──────────────────────────────────────
        stage('Push to Docker Hub') {
            steps {
                sh '''
                    printf '%s' "$DOCKER_CREDS_PSW" | docker login -u "$DOCKER_CREDS_USR" --password-stdin
                    for img in "$DOCKER_IMAGE_FRONTEND" "$DOCKER_IMAGE_BACKEND"; do
                        docker push "$img:$IMAGE_TAG"
                        docker push "$img:latest"
                    done
                '''
            }
            post {
                always { sh 'docker logout || true' }
            }
        }

        // ── STAGE 4 ──────────────────────────────────────
        stage('Deploy to EC2') {
            steps {
                sshagent(['app-server-ssh-key']) {
                    sh '''
                        ssh $SSH_OPTS "ubuntu@$APP_SERVER_IP" "mkdir -p ~/$APP_DIR"
                        scp $SSH_OPTS docker-compose.yml deploy.sh healthcheck.sh "ubuntu@$APP_SERVER_IP:~/$APP_DIR/"

                        # Password goes over stdin — not in argv, env or logs
                        printf '%s' "$DOCKER_CREDS_PSW" | ssh $SSH_OPTS "ubuntu@$APP_SERVER_IP" \
                            "chmod +x ~/$APP_DIR/*.sh && DOCKER_USERNAME='$DOCKER_USERNAME' IMAGE_TAG='$IMAGE_TAG' ~/$APP_DIR/deploy.sh"
                    '''
                }
            }
        }

        // ── STAGE 5 ──────────────────────────────────────
        stage('Health Check') {
            steps {
                sshagent(['app-server-ssh-key']) {
                    sh 'ssh $SSH_OPTS "ubuntu@$APP_SERVER_IP" "~/$APP_DIR/healthcheck.sh"'
                }
            }
        }
    }

    post {
        success {
            echo "Deployment SUCCESSFUL — Build #${env.BUILD_NUMBER} — App URL: http://${env.APP_SERVER_IP}"
        }
        failure {
            echo 'Pipeline FAILED — check the stage logs above'
        }
        always {
            cleanWs()
        }
    }
}
