# Catalyst Pipeline — Project Structure

```
catalyst-pipeline/
│
├── docker-compose.yml                  # Main orchestration file (see header for R7 / Ally X split)
├── .env.example                        # Copy to .env, fill in secrets (includes remote override vars)
│
├── db/
│   └── init.sql                        # Postgres schema (runs on first boot)
│
├── frontend/
│   ├── Dockerfile                      # Multi-stage build: npm build -> nginx serve
│   ├── nginx.conf                      # Serves static files + proxies /api/* and /mlflow/*
│   ├── package.json                    # React + Three.js + D3.js + Recharts
│   └── src/                            # React application code
│
├── api/
│   ├── Dockerfile                      # Python 3.11 + FastAPI + SQLAlchemy
│   └── app/
│       ├── main.py                     # FastAPI app, routes, middleware
│       ├── models.py                   # SQLAlchemy ORM models
│       ├── routes/
│       │   ├── candidates.py           # GET /candidates, filtering, ranking
│       │   ├── materials.py            # GET /materials, search, detail
│       │   ├── jobs.py                 # POST /jobs/train, POST /jobs/predict
│       │   └── mlflow.py               # Proxy MLflow run history
│       └── tasks.py                    # Celery task definitions (dispatched to workers)
│
├── workers/
│   ├── ingestion/
│   │   ├── Dockerfile                  # Python + pymatgen + requests
│   │   └── app/
│   │       ├── main.py                 # Celery worker entry point
│   │       ├── ingest_mp.py            # Materials Project ingestion logic
│   │       └── ingest_oc20.py          # OC20 dataset ingestion logic
│   │
│   ├── ml/
│   │   ├── Dockerfile                  # Python + PyTorch + PyTorch Geometric + CUDA
│   │   └── app/
│   │       ├── main.py                 # Celery worker entry point
│   │       ├── model.py                # GNN model definition (SchNet / MACE wrapper)
│   │       ├── train.py                # Training loop + MLflow logging
│   │       └── data.py                 # Dataset loading + featurization
│   │
│   └── prediction/
│       ├── Dockerfile                  # Same base as ml worker (minus CUDA — CPU only)
│       └── app/
│           ├── main.py                 # Celery worker entry point
│           ├── predict.py              # Batch inference + uncertainty estimation
│           └── active_learning.py      # Bayesian optimization + candidate ranking
│
└── monitoring/
    ├── prometheus.yml                  # Scrape targets
    ├── grafana-datasources/
    │   └── prometheus.yml              # Auto-provision Prometheus as a datasource
    └── grafana-dashboards/             # Drop JSON dashboard files here for auto-provisioning
```

## Which machine runs what

| Service                  | R7 (GPU + data layer) | Ally X (portable dev) |
|--------------------------|:---------------------:|:---------------------:|
| db (PostgreSQL)          | ✓                     |                       |
| redis                    | ✓                     |                       |
| mlflow                   | ✓                     |                       |
| data-ingestion-worker    | ✓                     | ✓ (connects to R7)   |
| ml-training-worker       | ✓ (needs 1080 Ti)     |                       |
| prediction-worker        |                       | ✓ (CPU-bound)         |
| api                      |                       | ✓                     |
| frontend                 |                       | ✓                     |
| prometheus / grafana     | ✓                     |                       |

For single-machine dev (everything local), just `docker compose up`. For the
split setup, see the remote override section at the bottom of `.env.example`.
