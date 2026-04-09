# Snake Game — Production Runbook

> **Service:** Snake Game
> **Owner:** DevOps Team
> **Repository:** https://github.com/jaya-narayana2205/snake-game
> **Last Updated:** 2026-04-09

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Deployment Steps](#2-deployment-steps)
3. [Rollback Procedure](#3-rollback-procedure)
4. [Common Issues & Troubleshooting](#4-common-issues--troubleshooting)
5. [On-Call Escalation Steps](#5-on-call-escalation-steps)

---

## 1. Architecture Overview

### 1.1 System Diagram

```
                         Internet
                            |
                     [ Node IP:30080 ]
                            |
                  +---------+---------+
                  |   K8s NodePort    |
                  |   Service (:80)   |
                  +---------+---------+
                            |
              +-------------+-------------+
              |                           |
     +--------+--------+        +--------+--------+
     |   Pod (Replica 1)  |        |   Pod (Replica 2)  |
     |   Nginx :8080    |        |   Nginx :8080    |
     |   index.html     |        |   index.html     |
     +------------------+        +------------------+
              |                           |
              +-------------+-------------+
                            |
                  +---------+---------+
                  |    ConfigMap       |
                  |    (nginx-config)  |
                  +-------------------+
```

### 1.2 Component Summary

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Application | HTML5 Canvas + Vanilla JS | Snake Game frontend |
| Web Server | Nginx 1.27 (Alpine) | Static file serving |
| Container | Docker (multi-stage) | Packaging and isolation |
| Orchestration | Kubernetes | Scheduling, scaling, self-healing |
| CI/CD | GitHub Actions | Automated lint, build, push |
| Registry | DockerHub | Container image storage |

### 1.3 Key Configuration Values

| Parameter | Value |
|-----------|-------|
| Docker Image | `<DOCKER_USERNAME>/snake-game` |
| Container Port | `8080` |
| K8s Service Port | `80` |
| NodePort | `30080` |
| Namespace | `snake-game` |
| Replicas (baseline) | `2` |
| Replicas (max via HPA) | `5` |
| HPA CPU Target | `70%` |
| CPU Request / Limit | `50m` / `200m` |
| Memory Request / Limit | `32Mi` / `64Mi` |
| Health Endpoint | `/healthz` |
| Readiness Endpoint | `/readyz` |
| Non-root User (UID) | `appuser (101)` |

### 1.4 Security Posture

- Container runs as non-root user (UID 101)
- Read-only root filesystem; writable dirs use `emptyDir` volumes
- All Linux capabilities dropped; `allowPrivilegeEscalation: false`
- Nginx security headers: CSP, X-Frame-Options, X-Content-Type-Options, XSS-Protection
- Hidden files blocked at Nginx level
- Docker image is minimal (~25 MB)

---

## 2. Deployment Steps

### 2.1 Prerequisites

- `kubectl` configured with cluster access
- `docker` CLI installed
- DockerHub credentials set as GitHub Secrets (`DOCKER_USERNAME`, `DOCKER_PASSWORD`)
- Kubernetes metrics-server installed (required for HPA)

```bash
# Verify cluster access
kubectl cluster-info

# Verify metrics-server is running
kubectl top nodes
```

### 2.2 First-Time Setup

**Step 1 — Create namespace and base resources:**

```bash
kubectl apply -f k8s/namespace.yml
```

**Step 2 — Deploy ConfigMap (Nginx configuration):**

```bash
kubectl apply -f k8s/configmap.yml
```

**Step 3 — Update the Docker image reference:**

Edit `k8s/deployment.yml` line 42 — replace `<DOCKER_USERNAME>` with your actual DockerHub username:

```yaml
image: yourusername/snake-game:latest
```

**Step 4 — Deploy the application:**

```bash
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml
kubectl apply -f k8s/hpa.yml
```

**Step 5 — Verify deployment:**

```bash
# Check all resources
kubectl -n snake-game get all

# Watch pods come up
kubectl -n snake-game get pods -w

# Verify health
kubectl -n snake-game describe deployment snake-game

# Test the endpoint
curl http://<NODE_IP>:30080
curl http://<NODE_IP>:30080/healthz
```

### 2.3 Subsequent Deployments (via CI/CD)

Deployments are automated through GitHub Actions on push to `main`:

```
Push to main → HTMLHint Lint → Docker Build → Push to DockerHub
```

After CI/CD pushes a new image, trigger a rollout:

```bash
# Restart pods to pull the latest image
kubectl -n snake-game rollout restart deployment/snake-game

# Monitor the rollout
kubectl -n snake-game rollout status deployment/snake-game
```

### 2.4 Manual Deployment (Emergency)

```bash
# Build locally
docker build -t yourusername/snake-game:hotfix-001 .

# Push to registry
docker push yourusername/snake-game:hotfix-001

# Update the deployment with the specific tag
kubectl -n snake-game set image deployment/snake-game \
  snake-game=yourusername/snake-game:hotfix-001

# Monitor
kubectl -n snake-game rollout status deployment/snake-game
```

### 2.5 Docker Compose (Staging/Local)

```bash
# Start
docker-compose up -d --build

# Verify
docker-compose ps
curl http://localhost:8080/healthz

# Stop
docker-compose down
```

---

## 3. Rollback Procedure

### 3.1 Quick Rollback (Last Known Good)

```bash
# Undo the most recent deployment
kubectl -n snake-game rollout undo deployment/snake-game

# Verify rollback completed
kubectl -n snake-game rollout status deployment/snake-game
```

### 3.2 Rollback to a Specific Revision

```bash
# List deployment history
kubectl -n snake-game rollout history deployment/snake-game

# View details of a specific revision
kubectl -n snake-game rollout history deployment/snake-game --revision=2

# Roll back to that revision
kubectl -n snake-game rollout undo deployment/snake-game --to-revision=2

# Verify
kubectl -n snake-game rollout status deployment/snake-game
```

### 3.3 Rollback to a Specific Image Tag

```bash
# Set a known-good image tag
kubectl -n snake-game set image deployment/snake-game \
  snake-game=yourusername/snake-game:<known-good-sha>

# Monitor
kubectl -n snake-game rollout status deployment/snake-game
```

### 3.4 Post-Rollback Checklist

- [ ] Confirm all pods are Running and Ready
- [ ] Verify `/healthz` returns `200 ok`
- [ ] Verify `/readyz` returns `200 ready`
- [ ] Test game loads in browser at `http://<NODE_IP>:30080`
- [ ] Check HPA is functioning: `kubectl -n snake-game get hpa`
- [ ] Notify the team that a rollback occurred and why

---

## 4. Common Issues & Troubleshooting

### 4.1 Pods Not Starting

**Symptom:** Pods stuck in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff`.

```bash
# Get pod status
kubectl -n snake-game get pods

# Describe the failing pod
kubectl -n snake-game describe pod <pod-name>

# Check container logs
kubectl -n snake-game logs <pod-name>
```

| Status | Likely Cause | Fix |
|--------|-------------|-----|
| `ImagePullBackOff` | Wrong image name, tag doesn't exist, or DockerHub auth failure | Verify image exists: `docker pull yourusername/snake-game:latest` |
| `CrashLoopBackOff` | Nginx config error or permission issue | Check logs: `kubectl -n snake-game logs <pod>` |
| `Pending` | Insufficient cluster resources (CPU/memory) | Check node capacity: `kubectl describe nodes` |
| `ContainerCreating` (stuck) | ConfigMap not found or volume mount issue | Verify ConfigMap: `kubectl -n snake-game get configmap nginx-config` |

### 4.2 Health Check Failures

**Symptom:** Pods restarting frequently; `RESTARTS` count increasing.

```bash
# Check probe failures in events
kubectl -n snake-game describe pod <pod-name> | grep -A5 "Events"

# Test health endpoint from inside the cluster
kubectl -n snake-game exec <pod-name> -- wget -qO- http://localhost:8080/healthz
```

| Probe | Endpoint | Failure Behaviour |
|-------|----------|-------------------|
| Liveness (`/healthz`) | Returns `200 ok` | Pod is **killed and restarted** after 3 consecutive failures |
| Readiness (`/readyz`) | Returns `200 ready` | Pod is **removed from Service** (no traffic) after 2 failures |

**Fixes:**
- Check Nginx is running: `kubectl -n snake-game exec <pod> -- ps aux`
- Verify ConfigMap is mounted: `kubectl -n snake-game exec <pod> -- cat /etc/nginx/conf.d/default.conf`
- Check Nginx error log: `kubectl -n snake-game exec <pod> -- cat /var/log/nginx/error.log`

### 4.3 Service Not Accessible

**Symptom:** Cannot reach `http://<NODE_IP>:30080`.

```bash
# Verify service exists and has endpoints
kubectl -n snake-game get svc
kubectl -n snake-game get endpoints snake-game

# Check NodePort is allocated
kubectl -n snake-game describe svc snake-game

# Test from within the cluster
kubectl -n snake-game run curl-test --image=curlimages/curl --rm -it -- \
  curl -s http://snake-game.snake-game.svc.cluster.local/healthz
```

| Issue | Cause | Fix |
|-------|-------|-----|
| No endpoints listed | No pods match the selector `app: snake-game` | Check pod labels: `kubectl -n snake-game get pods --show-labels` |
| Connection refused on NodePort | Firewall blocking port 30080 | Open port 30080 in cloud security group / firewall rules |
| Service exists but timeout | Pods are not ready | Check readiness probe status in pod describe output |

### 4.4 HPA Not Scaling

**Symptom:** HPA shows `<unknown>` for CPU metrics or doesn't scale.

```bash
# Check HPA status
kubectl -n snake-game get hpa
kubectl -n snake-game describe hpa snake-game
```

| Issue | Cause | Fix |
|-------|-------|-----|
| `<unknown>/70%` CPU | metrics-server not installed | Install metrics-server: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |
| Not scaling up | CPU below 70% threshold | Verify with `kubectl -n snake-game top pods` |
| Not scaling down | Stabilization window (120s) active | Wait 2 minutes; this is by design to prevent flapping |

### 4.5 CI/CD Pipeline Failures

```bash
# Check pipeline runs
gh run list --repo jaya-narayana2205/snake-game

# View logs for a specific run
gh run view <run-id> --log --repo jaya-narayana2205/snake-game
```

| Job | Common Failure | Fix |
|-----|---------------|-----|
| **Lint** | HTMLHint rule violation | Fix the HTML error shown in the log; check `.htmlhintrc` rules |
| **Build** | Dockerfile syntax or missing file | Verify `src/index.html` exists; check Dockerfile `COPY` paths |
| **Push** | DockerHub auth failure | Verify `DOCKER_USERNAME` and `DOCKER_PASSWORD` secrets in repo Settings |

### 4.6 Nginx Configuration Errors

**Symptom:** Pods crash immediately after starting.

```bash
# Test Nginx config syntax locally
docker run --rm -v $(pwd)/docker/nginx.conf:/etc/nginx/conf.d/default.conf \
  nginx:1.27-alpine nginx -t
```

Common Nginx config mistakes:
- Missing semicolons at end of directives
- Duplicate `listen` directives
- Invalid characters in `add_header` values
- Incorrect `root` path (must be `/usr/share/nginx/html`)

---

## 5. On-Call Escalation Steps

### 5.1 Severity Levels

| Severity | Definition | Response Time | Example |
|----------|-----------|---------------|---------|
| **SEV-1** | Service completely down, no pods running | 15 minutes | All pods in CrashLoopBackOff |
| **SEV-2** | Service degraded, partial availability | 30 minutes | 1 of 2 pods down, increased latency |
| **SEV-3** | Non-critical issue, service operational | 4 hours | HPA not scaling, stale image |
| **SEV-4** | Informational, no user impact | Next business day | CI/CD warning, resource optimization |

### 5.2 Escalation Flowchart

```
Alert Triggered
      |
      v
+------------------+
| On-Call Engineer  |  <-- First Responder (15 min SLA)
+--------+---------+
         |
         |-- Can resolve? --YES--> Fix + Document
         |
         NO
         |
         v
+------------------+
| DevOps Lead      |  <-- Escalation Level 1 (30 min SLA)
+--------+---------+
         |
         |-- Can resolve? --YES--> Fix + Document
         |
         NO
         |
         v
+------------------+
| Engineering       |  <-- Escalation Level 2 (1 hour SLA)
| Manager           |
+------------------+
```

### 5.3 Immediate Response Checklist

When paged, run these commands in order:

```bash
# 1. Get the current state of all resources
kubectl -n snake-game get all

# 2. Check pod health and recent events
kubectl -n snake-game get pods -o wide
kubectl -n snake-game get events --sort-by='.lastTimestamp' | tail -20

# 3. Check for failing probes
kubectl -n snake-game describe pods | grep -A3 "Liveness\|Readiness"

# 4. Read logs from all pods
kubectl -n snake-game logs -l app=snake-game --tail=50

# 5. Verify the service has healthy endpoints
kubectl -n snake-game get endpoints snake-game

# 6. Check HPA status
kubectl -n snake-game get hpa

# 7. Test externally
curl -o /dev/null -s -w "%{http_code}" http://<NODE_IP>:30080/healthz
```

### 5.4 Decision Matrix

| Observation | Action |
|-------------|--------|
| All pods CrashLoopBackOff | Roll back immediately (Section 3.1), then investigate |
| 1 pod down, 1 healthy | Monitor for 5 minutes; K8s should self-heal. If not, delete the failing pod |
| ImagePullBackOff | Check DockerHub — image may be missing. Redeploy with a known-good tag |
| Nodes NotReady | Cluster-level issue — escalate to infrastructure team |
| HPA at max replicas (5) | Possible traffic spike or resource leak. Check `kubectl top pods` and scale limits |
| `/healthz` returns non-200 | Nginx misconfiguration — check ConfigMap and pod logs |
| Service has 0 endpoints | No ready pods — check readiness probe and pod status |

### 5.5 Post-Incident

After resolving any SEV-1 or SEV-2 incident:

1. **Document** what happened, when, and what fixed it
2. **Identify** root cause (bad deploy, config error, infra failure)
3. **Create** follow-up tickets for preventive measures
4. **Update** this runbook if a new failure mode was discovered
5. **Communicate** resolution to stakeholders

---

## Appendix

### Useful Commands Cheat Sheet

```bash
# Quick status
kubectl -n snake-game get all

# Watch pods in real time
kubectl -n snake-game get pods -w

# Pod resource usage
kubectl -n snake-game top pods

# Shell into a running pod
kubectl -n snake-game exec -it <pod-name> -- /bin/sh

# Force delete a stuck pod
kubectl -n snake-game delete pod <pod-name> --grace-period=0 --force

# View rollout history
kubectl -n snake-game rollout history deployment/snake-game

# Scale manually (overrides HPA temporarily)
kubectl -n snake-game scale deployment/snake-game --replicas=3

# Restart all pods (rolling)
kubectl -n snake-game rollout restart deployment/snake-game

# View ConfigMap content
kubectl -n snake-game get configmap nginx-config -o yaml

# Check GitHub Actions status
gh run list --repo jaya-narayana2205/snake-game
```

### File Reference

| File | Purpose |
|------|---------|
| `src/index.html` | Snake Game application |
| `Dockerfile` | Multi-stage production build |
| `docker/nginx.conf` | Nginx config (standalone Docker) |
| `docker-compose.yml` | Local/staging deployment |
| `k8s/namespace.yml` | Kubernetes namespace |
| `k8s/configmap.yml` | Nginx config for K8s |
| `k8s/deployment.yml` | Pod deployment spec |
| `k8s/service.yml` | NodePort service |
| `k8s/hpa.yml` | Horizontal Pod Autoscaler |
| `.github/workflows/deploy.yml` | CI/CD pipeline |
| `setup.sh` | Git repo initialization script |
