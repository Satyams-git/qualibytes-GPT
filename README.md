# 🤖 Qualibytes GPT

> A self-hosted AI chat application powered by **tinyllama** via **Ollama** — deployed using a full CI/CD pipeline on **AWS EC2**.

![Architecture](https://img.shields.io/badge/Architecture-3--Container-blue)
![Model](https://img.shields.io/badge/Model-tinyllama-orange)
![CI/CD](https://img.shields.io/badge/CI%2FCD-Jenkins%20%7C%20GitLab-green)
![Platform](https://img.shields.io/badge/Platform-AWS%20EC2-yellow)

---

## 📋 Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Prerequisites](#4-prerequisites)
5. [EC2 Server Setup](#5-ec2-server-setup)
6. [Run Locally with Docker Compose](#6-run-locally-with-docker-compose)
7. [Part A — Jenkins CI/CD](#7-part-a--jenkins-cicd)
8. [Part B — GitLab CI/CD](#8-part-b--gitlab-cicd)
9. [Verification Checklist](#9-verification-checklist)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Project Overview

Qualibytes GPT is a 3-container application:

| Service | Technology | What it does |
|---------|-----------|--------------|
| **frontend** | Nginx + HTML/JS | ChatGPT-style chat UI |
| **backend** | Python Flask | API that talks to Ollama |
| **ollama** | Ollama (tinyllama) | Runs the AI model locally |

All three containers run on a shared Docker network (`qualibytes-network`) and are managed by Docker Compose.

---

## 2. Architecture

```
Browser
   │
   ▼
[Frontend — Port 80]  ← Nginx serves HTML/JS
   │
   │  /api/chat  (proxy_pass)
   ▼
[Backend — Port 5000]  ← Python Flask
   │
   │  http://ollama:11434/api/chat
   ▼
[Ollama — Port 11434]  ← tinyllama model
```

**CI/CD Flow:**

```
Code Push (GitHub / GitLab)
       │
       ▼
Jenkins / GitLab Runner
       │
  ┌────┴────────────────────────────┐
  │ Build Frontend & Backend Images │
  │ Push to Docker Hub              │
  │ SSH into App Server             │
  │ docker compose pull & up        │
  │ Health Check                    │
  └─────────────────────────────────┘
       │
       ▼
  App live on EC2 :80
```

---

## 3. Repository Structure

```
qualibytes-gpt/
├── frontend/
│   ├── Dockerfile          ← Nginx image
│   ├── nginx.conf          ← Proxy /api/* to backend
│   └── index.html          ← Chat UI
├── backend/
│   ├── Dockerfile          ← Python image
│   ├── app.py              ← Flask API
│   └── requirements.txt    ← Flask, requests, gunicorn
├── docker-compose.yml      ← All 3 services + network + volume
├── setup.sh                ← First-time LOCAL setup (builds from source)
├── deploy.sh               ← Runs on the App Server: pull images + start (used by CI)
├── healthcheck.sh          ← Runs on the App Server: post-deploy checks (used by CI)
├── Jenkinsfile             ← Jenkins Declarative Pipeline
├── .gitlab-ci.yml          ← GitLab CI/CD Pipeline
├── .gitignore
└── README.md               ← You are here
```

---

## 4. Prerequisites

### On your local machine:
- Git installed
- GitHub or GitLab account

### On AWS EC2 (App Server — t2.small minimum):
- Ubuntu 22.04 LTS
- Docker installed
- Docker Compose installed
- Ports open: **22, 80** (5000 and 11434 stay private — see 5.1)

### Accounts needed:
- [Docker Hub](https://hub.docker.com) — free account (image storage)

---

## 5. EC2 Server Setup

### 5.1 Launch EC2
- AMI: Ubuntu Server 22.04 LTS
- Instance type: **t2.small** (2GB RAM — minimum for tinyllama)
- Security Group — open these ports:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH access (restrict to your IP + the Jenkins server) |
| 80 | TCP | Web app (frontend) |
| 8080 | TCP | Jenkins (Jenkins server only, restrict to your IP) |

> ⚠️ Do **not** open 5000 or 11434. The backend is bound to `127.0.0.1:5000`
> on the server and Ollama has no published port at all — Ollama has no
> authentication, so a public 11434 lets anyone use your server's CPU/RAM
> and fill its disk with models. Test them from the server itself.

### 5.2 Install Docker on EC2

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install docker.io docker-compose-v2 -y
sudo systemctl enable docker
sudo systemctl start docker

# Add ubuntu user to docker group (no sudo needed)
sudo usermod -aG docker ubuntu

# Log out and back in for group change to take effect
exit
```

### 5.3 Verify Installation

```bash
docker --version        # Docker version 24.x.x
docker compose version  # Docker Compose version 2.x.x
```

---

## 6. Run Locally with Docker Compose

Use this to test the app before setting up CI/CD.

### Step 1 — Clone the repo

```bash
git clone https://github.com/Satyams-git/qualibytes-GPT.git qualibytes-gpt
cd qualibytes-gpt
```

### Step 2 — Run setup script (first time only)

```bash
chmod +x setup.sh
./setup.sh
```

This will:
1. Build the frontend & backend images and start all 3 containers
2. Wait for Ollama to be ready
3. Download the tinyllama model (~637MB)

### Step 3 — Open in browser

```
http://YOUR-EC2-PUBLIC-IP
```

### Step 4 — Verify all containers are running

```bash
docker compose ps
```

Expected output:
```
NAME                    STATUS
qualibytes-frontend     Up
qualibytes-backend      Up
qualibytes-ollama       Up
```

### Useful Docker Compose Commands

```bash
# View real-time logs
docker compose logs -f

# View logs for one service
docker compose logs -f backend

# Restart a single service
docker compose restart backend

# Stop everything
docker compose down

# Stop and delete volumes (removes downloaded model!)
docker compose down -v
```

---

## 7. Part A — Jenkins CI/CD

### 7.1 Jenkins Server Setup

On your Jenkins EC2 (separate from App Server):

```bash
# Install Java
sudo apt update
sudo apt install openjdk-17-jdk -y

# Add Jenkins repo
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install jenkins -y
sudo systemctl enable --now jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open `http://JENKINS-SERVER-IP:8080` and complete setup.

### 7.2 Required Jenkins Plugins

Go to **Manage Jenkins → Plugins → Available** and install:

- Git Plugin
- Docker Pipeline Plugin
- SSH Agent Plugin
- Pipeline Plugin (usually pre-installed)
- Timestamper (usually pre-installed)

### 7.3 Add Credentials

Go to **Manage Jenkins → Credentials → System → Global → Add Credential**:

| ID | Type | Value |
|----|------|-------|
| `dockerhub-credentials` | Username with password | Docker Hub login |
| `app-server-ssh-key` | SSH Username with private key | `ubuntu` + your `.pem` key content |

### 7.4 Add Environment Variables

Go to **Manage Jenkins → System → Global Properties → Environment Variables**:

| Name | Value |
|------|-------|
| `DOCKER_USERNAME` | your Docker Hub username |
| `APP_SERVER_IP` | your App Server public IP |

### 7.5 Allow Jenkins to Run Docker

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### 7.6 Create Pipeline Job

1. Jenkins Dashboard → **New Item**
2. Name: `qualibytes-gpt`
3. Type: **Pipeline** → OK
4. Under Pipeline section:
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/Satyams-git/qualibytes-GPT.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
5. **Save** → **Build Now**

### 7.7 What the pipeline does

| Stage | What happens |
|-------|--------------|
| Build | Builds both images, tagged `:BUILD_NUMBER` and `:latest` |
| Push | Pushes both tags to Docker Hub |
| Deploy | Copies `docker-compose.yml`, `deploy.sh`, `healthcheck.sh` to `~/qualibytes-gpt/` on the App Server and runs `deploy.sh` with `IMAGE_TAG=BUILD_NUMBER` |
| Health Check | Runs `healthcheck.sh` on the App Server (backend, model, frontend, one real chat) |

The Docker Hub password is sent to the server over SSH **stdin**, so it never
shows up in the build log or the server's process list.

**Rollback:** on the App Server run
`cd ~/qualibytes-gpt && DOCKER_USERNAME=<you> IMAGE_TAG=<old build number> ./deploy.sh`

### 7.8 Add GitHub Webhook (Auto-trigger)

1. Go to your GitHub repo → **Settings → Webhooks → Add webhook**
2. Payload URL: `http://JENKINS-IP:8080/github-webhook/`
3. Content type: `application/json`
4. Event: **Just the push event**
5. **Add webhook**

Now every `git push` will auto-trigger Jenkins!

---

## 8. Part B — GitLab CI/CD

### 8.1 Push code to GitLab

```bash
# Add GitLab as a second remote
git remote add gitlab https://gitlab.com/YOUR-GITLAB-USERNAME/qualibytes-gpt.git

# Push to GitLab
git push gitlab main
```

### 8.2 Install GitLab Runner on App Server

```bash
# Add GitLab Runner repo
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt install gitlab-runner -y

# The jobs don't install packages (the runner isn't root) — install these once
sudo apt install -y openssh-client curl

# Add runner to docker group
sudo usermod -aG docker gitlab-runner
sudo systemctl restart gitlab-runner
```

### 8.3 Register the Runner

1. Go to your GitLab project → **Settings → CI/CD → Runners**
2. Copy the **registration token**
3. On your EC2:

```bash
sudo gitlab-runner register
```

When prompted:
```
URL: https://gitlab.com
Token: (paste your token)
Description: ec2-runner
Tags: ec2
Executor: shell
```

### 8.4 Add CI/CD Variables

Go to **GitLab → Project → Settings → CI/CD → Variables → Add variable**:

| Key | Value | Masked |
|-----|-------|--------|
| `DOCKER_USERNAME` | your Docker Hub username | No |
| `DOCKER_PASSWORD` | your Docker Hub password | **Yes** |
| `APP_SERVER_IP` | your App Server IP | No |
| `SSH_PRIVATE_KEY` | content of your `.pem` file | **Yes** |

### 8.5 Trigger the Pipeline

Push any change to the `main` branch:

```bash
git add .
git commit -m "Trigger GitLab pipeline"
git push gitlab main
```

Go to **GitLab → CI/CD → Pipelines** to watch it run.

---

## 9. Verification Checklist

After pipeline runs successfully, verify:

```bash
# Run these ON the App Server (5000 is bound to localhost only)
cd ~/qualibytes-gpt

# 0. Everything at once
./healthcheck.sh

# 1. All containers running
docker compose ps

# 2. Backend health check
curl http://localhost:5000/health
# Expected: {"status": "OK", "app": "Qualibytes GPT Backend", "model": "tinyllama"}

# 3. tinyllama is downloaded
docker exec qualibytes-ollama ollama list
# Expected: tinyllama listed

# 4. Test a chat API call directly
curl -X POST http://localhost:5000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Say hello"}]}'

# 5. Frontend is accessible
curl -I http://YOUR-EC2-IP
# Expected: HTTP/1.1 200 OK
```

---

## 10. Troubleshooting

### ❌ `docker: permission denied`
**Cause:** User is not in the docker group.
```bash
sudo usermod -aG docker $USER       # For ubuntu user
sudo usermod -aG docker jenkins     # For Jenkins
sudo usermod -aG docker gitlab-runner  # For GitLab Runner
# Then restart: sudo systemctl restart jenkins / gitlab-runner
```

---

### ❌ `docker compose: command not found`
**Cause:** Docker Compose v2 plugin is missing. This project uses `docker compose` (with a space) everywhere — the old v1 `docker-compose` binary is not used.
```bash
# Install Docker Compose v2
sudo apt install docker-compose-v2 -y
docker compose version   # Should show v2.x.x
```

---

### ❌ Backend returns `Ollama service is not reachable`
**Cause:** Ollama container not running or still starting.
```bash
# Check if ollama is running
docker compose ps
docker compose logs ollama

# Restart it
docker compose restart ollama

# Wait ~10s then try again
docker exec qualibytes-ollama ollama list
```

---

### ❌ `tinyllama not found` / Model not loaded
**Cause:** Model was never pulled into the Ollama container.
```bash
# Pull the model manually
docker exec qualibytes-ollama ollama pull tinyllama

# Verify
docker exec qualibytes-ollama ollama list
```

---

### ❌ `502 Bad Gateway` on port 80
**Cause:** Nginx can't reach the backend container.
```bash
# Check if backend is running
docker compose ps
docker compose logs backend

# Restart backend
docker compose restart backend

# Check nginx config
docker exec qualibytes-frontend nginx -t
```

---

### ❌ Chat returns `Ollama timed out`
**Cause:** tinyllama is slow on t2.small — first response takes 30-60 seconds.
- This is normal on first message after container start.
- The model warms up after first call.
- Increase timeout in `backend/app.py` if needed (`timeout=90`).

---

### ❌ SSH: `Permission denied (publickey)`
**Cause:** Wrong SSH key in Jenkins/GitLab credentials.
```bash
# Test SSH manually from CI server
ssh -i /path/to/key.pem ubuntu@APP-SERVER-IP

# If it works, the key is correct — re-add it to credentials
```

---

### ❌ Docker Hub push fails with `unauthorized`
**Cause:** Wrong Docker credentials.
```bash
# Test manually on CI server
docker login
# Enter username and password
# If it works, re-add credentials in Jenkins/GitLab
```

---

### ❌ Jenkins pipeline: `ssh: connect to host port 22: Connection refused`
**Cause:** App Server security group doesn't allow SSH from Jenkins server.
- Go to AWS Console → Security Group of App Server → Inbound Rules
- Add rule: **SSH (port 22) from Jenkins Server IP**

---

### ❌ GitLab Runner: `This job is stuck — no runner available`
**Cause:** Runner tag mismatch or runner is offline.
```bash
# Check runner status
sudo gitlab-runner status

# Restart if needed
sudo systemctl restart gitlab-runner

# Check tags: .gitlab-ci.yml has `tags: [ec2]`
# Runner must also have tag `ec2` — re-register if needed
```

---

### ❌ `Port 80 already in use`
**Cause:** Nginx is running on the host and also inside Docker.
```bash
# Check what's using port 80
sudo lsof -i :80

# Stop host nginx if running
sudo systemctl stop nginx
sudo systemctl disable nginx

# Now start Docker containers
docker compose up -d
```

---

*Built with ❤️ for learning CI/CD — Qualibytes Training*
