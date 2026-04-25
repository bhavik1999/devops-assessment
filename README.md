# DevOps Assessment — k3s + ArgoCD + LGTM Stack

> **Stack:** Ubuntu 24.04 · k3s · ArgoCD · Prometheus · Grafana · Loki · Tempo · FastAPI

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         k3s Cluster                              │
│                                                                  │
│  ┌──────────┐      ┌──────────────────────────────────────────┐  │
│  │  ArgoCD  │─────▶│     GitOps Repository (this repo)        │  │
│  └──────────┘      └──────────────────────────────────────────┘  │
│       │                                                          │
│       ├── namespace: observability                               │
│       │     ├── Prometheus  (metrics scraping + storage)         │
│       │     ├── Grafana     (dashboards + explore UI)            │
│       │     ├── Loki        (log aggregation)                    │
│       │     ├── Promtail    (log collector → Loki)               │
│       │     └── Tempo       (distributed tracing)               │
│       │                                                          │
│       └── namespace: sample-api                                  │
│             └── FastAPI     (emits logs + metrics + traces)      │
└──────────────────────────────────────────────────────────────────┘
```

All deployments are managed via **ArgoCD App-of-Apps pattern** — the only manual step after cluster bootstrap is applying the root ArgoCD application. Everything else is GitOps-driven.

---

## Repository Structure

```
.
├── bootstrap/
│   ├── 01-install-k3s.sh          # Installs k3s with traefik/servicelb disabled
│   ├── 02-install-argocd.sh       # Installs ArgoCD and applies app-of-apps
│   └── 03-simulate-traffic.sh     # Generates live API traffic for observability
├── gitops/
│   ├── apps/                      # ArgoCD Application manifests (app-of-apps children)
│   │   ├── prometheus-stack.yaml  # kube-prometheus-stack (Prometheus + Grafana)
│   │   ├── loki.yaml              # Loki log aggregation
│   │   ├── promtail.yaml          # Promtail log collector
│   │   ├── tempo.yaml             # Tempo distributed tracing
│   │   └── sample-api.yaml        # Sample FastAPI application
│   └── infrastructure/
│       ├── argocd/
│       │   └── app-of-apps.yaml   # Root ArgoCD application
│       ├── namespaces/
│       │   └── namespaces.yaml    # Namespace definitions
│       └── observability/
│           └── dashboards/        # Exported Grafana dashboard JSONs
├── sample-api/
│   ├── Dockerfile
│   ├── src/
│   │   ├── main.py                # FastAPI app with metrics, logs, traces
│   │   └── requirements.txt
│   └── k8s/
│       ├── deployment.yaml        # Deployment with OTLP env config
│       ├── service.yaml           # ClusterIP service
│       └── servicemonitor.yaml    # Prometheus ServiceMonitor
└── docs/
    ├── bootstrap-guide.md         # Detailed setup guide
    └── ai-interaction-log.md      # AI tooling usage log
```

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Ubuntu | 24.04 | Host OS |
| Docker | 24+ | Build API image |
| kubectl | latest | Cluster management |
| Helm | 3+ | Chart deployments |
| k3s | latest | Lightweight Kubernetes |

### Bootstrap from Scratch

```bash
# 1. Clone the repository
git clone https://github.com/bhavik1999/devops-assessment.git
cd devops-assessment

# 2. Install k3s
./bootstrap/bootstrap.sh
```

---

## Accessing the UIs

Run each port-forward in a **separate terminal**:

| Service | Port-forward Command | URL | Credentials |
|---------|---------------------|-----|-------------|
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 | admin / *(see below)* |
| Grafana | `kubectl port-forward svc/prometheus-stack-grafana -n observability 3000:80` | http://localhost:3000 | admin / admin123 |
| Prometheus | `kubectl port-forward svc/prometheus-stack-kube-prom-prometheus -n observability 9090:9090` | http://localhost:9090 | — |
| Sample API | `kubectl port-forward svc/sample-api -n sample-api 8888:80` | http://localhost:8888 | — |

Get ArgoCD admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Observability Stack

### Metrics (Prometheus + Grafana)

Prometheus scrapes the sample API via a `ServiceMonitor` in the `observability` namespace. Key metrics exposed:

| Metric | Description |
|--------|-------------|
| `api_request_total` | Total requests by method, endpoint, status |
| `api_request_duration_seconds` | Request latency histogram |
| `api_error_total` | Total errors by endpoint |

**Grafana Dashboards imported:**
- Node Exporter Full (ID: `1860`)
- Kubernetes Cluster Overview (ID: `7249`)
- Loki Dashboard (ID: `13639`)
- FastAPI Observability (ID: `17175`)
- Custom: **Sample API — Full Observability** (exported JSON in `gitops/infrastructure/observability/dashboards/`)

### Logs (Loki + Promtail)

Promtail collects logs from all pods and ships to Loki. Query in Grafana Explore:
```
{namespace="sample-api"} | json
```

### Traces (Tempo + OpenTelemetry)

The sample API uses OpenTelemetry with the OTLP HTTP exporter to send traces to Tempo on port `4318`. Query in Grafana Explore → Tempo → Search → Service Name: `sample-api`.

---

## Sample API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Service info |
| GET | `/health` | Health check (used by probes) |
| GET | `/users` | List all users |
| GET | `/users/{id}` | Get user by ID (404 if id > 100) |
| POST | `/orders` | Create an order |
| GET | `/orders/{id}/status` | Get order status |
| GET | `/slow` | Intentionally slow endpoint (0.5–2s) |
| GET | `/error` | Intentionally returns 500 |
| GET | `/metrics` | Prometheus metrics scrape endpoint |

---

## GitOps Flow

```
Git Push → ArgoCD detects change → Syncs to k3s cluster
```

ArgoCD watches `gitops/apps/` via the app-of-apps pattern. Any change pushed to `main` is automatically applied to the cluster within ~3 minutes (default sync interval).

Force a sync immediately:
```bash
argocd app sync app-of-apps
argocd app sync prometheus-stack
argocd app sync sample-api
```

---

## Useful Commands

```bash
# Check all pods across cluster
kubectl get pods -A

# Check ArgoCD application status
argocd app list

# Follow sample API logs live
kubectl logs -n sample-api -l app=sample-api -f

# Check Prometheus targets (is sample-api UP?)
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E "sample-api|health"

# Check all PVCs (persistent storage)
kubectl get pvc -A

# Restart sample API deployment
kubectl rollout restart deployment/sample-api -n sample-api

# Run traffic simulation (120 seconds)
./bootstrap/03-simulate-traffic.sh 120
```

---

## Troubleshooting

**Prometheus pod stuck in Pending/CrashLoop:**
```bash
kubectl get pvc -n observability
kubectl describe pod -n observability -l app.kubernetes.io/name=prometheus | tail -20
```

**ServiceMonitor not picked up by Prometheus:**
```bash
# ServiceMonitor must be in observability namespace with label release: prometheus-stack
kubectl get servicemonitor -n observability
```

**Sample API traces not appearing in Tempo:**
```bash
# Verify OTLP HTTP endpoint is set correctly
kubectl exec -n sample-api \
  $(kubectl get pod -n sample-api -l app=sample-api -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep TEMPO
# Should show: TEMPO_ENDPOINT=http://tempo.observability.svc.cluster.local:4318/v1/traces
```

**Port already in use:**
```bash
pkill -f "port-forward" && sleep 2
# Then re-run your port-forward commands
```

---

## Final Checklist

- [x] k3s cluster running — `kubectl get nodes`
- [x] ArgoCD healthy — `argocd app list`
- [x] All LGTM pods running — `kubectl get pods -n observability`
- [x] Sample API running — `kubectl get pods -n sample-api`
- [x] Prometheus scraping API — Prometheus UI → Status → Targets → sample-api: UP
- [x] Logs flowing to Loki — Grafana → Explore → Loki → `{namespace="sample-api"}`
- [x] Traces flowing to Tempo — Grafana → Explore → Tempo → service: sample-api
- [x] Traffic simulation generates live graphs in Grafana
- [x] Git history tells a meaningful story with conventional commits
- [x] AI interaction log documented in `docs/ai-interaction-log.md`

---

*DevOps Assessment — Mid-Senior Level*
*Stack: Ubuntu 24.04 · k3s · ArgoCD · Prometheus · Grafana · Loki · Tempo · FastAPI*
