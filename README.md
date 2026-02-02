# Atlantis

**A catalyst discovery pipeline built on active learning.**

The name is a portmanteau of *Atlanta* and the idea of a catalyst — something that accelerates change without being consumed by it. Water splitting, CO₂ reduction, and other catalytic processes sit at the intersection of materials science and climate impact. Atlantis exists to make the search for better catalysts faster by replacing brute-force screening with an intelligent feedback loop.

## What it does

The search space of possible catalyst materials is astronomically large. Traditional lab work tests one material at a time. Atlantis flips that — it screens millions of candidates *in silico* using graph neural networks, surfaces the ones most worth testing in a real lab, and feeds validation results back into the model so each iteration gets smarter.

The pipeline ingests materials data from public databases (Materials Project, OC20), trains GNN models to predict catalytic properties, uses Bayesian optimization to rank candidates by a combination of predicted performance and model uncertainty, and tracks the full lifecycle from initial ranking through experimental validation.

## System architecture

```mermaid
graph TB
    subgraph frontend_net["frontend_net"]
        FE[Frontend<br/>React + Nginx<br/>:3000]
        API[API Server<br/>FastAPI<br/>:8000]
    end

    subgraph backend_net["backend_net"]
        API
        DB[(PostgreSQL 16<br/>:5432)]
        Redis[(Redis 7<br/>:6379)]
        MLflow[MLflow<br/>:5000]
        Ingestion[Data Ingestion<br/>Worker]
        Prediction[Prediction<br/>Worker]
        Training[ML Training<br/>Worker]
        Prometheus[Prometheus<br/>:9090]
        Grafana[Grafana<br/>:3001]
    end

    subgraph ml_net["ml_net"]
        MLflow
        Training
        Prediction
    end

    FE -->|/api/*| API
    FE -->|/mlflow/*| MLflow
    API --> DB
    API --> Redis
    API --> MLflow
    Ingestion --> DB
    Ingestion --> Redis
    Training --> DB
    Training --> Redis
    Training --> MLflow
    Training -.->|GPU| GPU{{NVIDIA 1080 Ti}}
    Prediction --> DB
    Prediction --> Redis
    Prediction --> MLflow
    Prometheus --> API
    Prometheus --> Training
    Prometheus --> Prediction
    Prometheus --> Ingestion
    Grafana --> Prometheus
```

## Active learning loop

```mermaid
graph LR
    A[Ingest data<br/>MP / OC20] --> B[Train GNN<br/>model]
    B --> C[Predict across<br/>candidate pool]
    C --> D[Active learning<br/>ranks candidates]
    D --> E[Researcher selects<br/>& validates]
    E --> F[Validation results<br/>become training data]
    F --> B
```

Each iteration of this loop should make the model better. The active learning step is what makes it *efficient* — you're not validating randomly, you're validating the materials most likely to teach the model something new or reveal something valuable.

## Database schema

```mermaid
erDiagram
    materials {
        int id PK
        varchar source
        varchar source_id
        varchar formula
        varchar crystal_system
        int space_group
        int num_atoms
        jsonb properties
        jsonb structure_json
        timestamp created_at
        timestamp updated_at
    }

    predictions {
        int id PK
        int material_id FK
        varchar model_run_id
        varchar target_property
        float predicted_value
        float uncertainty
        float confidence
        timestamp created_at
    }

    candidates {
        int id PK
        int material_id FK
        int prediction_id FK
        float acquisition_score
        float exploration_weight
        float exploitation_weight
        int rank
        varchar status
        text notes
        varchar flagged_by
        timestamp created_at
        timestamp updated_at
    }

    validation_results {
        int id PK
        int candidate_id FK
        int material_id FK
        varchar validation_method
        varchar target_property
        float measured_value
        float measurement_error
        varchar validated_by
        text notes
        timestamp created_at
    }

    active_learning_runs {
        int id PK
        timestamp run_timestamp
        varchar model_run_id
        int num_candidates_scored
        int num_candidates_selected
        float exploration_weight
        varchar strategy
        text notes
    }

    materials ||--o{ predictions : "has"
    materials ||--o{ candidates : "has"
    predictions ||--o{ candidates : "selects"
    candidates ||--o{ validation_results : "validated by"
    materials ||--o{ validation_results : "validated for"
```

## Candidate lifecycle

```mermaid
stateDiagram-v2
    [*] --> ranked : Active learning scores candidate
    ranked --> flagged : Researcher flags for review
    flagged --> in_validation : Validation begins (DFT / experiment)
    in_validation --> validated : Results confirm potential
    in_validation --> rejected : Results negative
    validated --> [*]
    rejected --> [*]

    note right of validated : Feeds back as new training data
```

## Tech stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Database | PostgreSQL 16 | JSONB columns for variable-schema material properties |
| Cache / Broker | Redis 7 | Celery message broker + prediction cache |
| ML Tracking | MLflow 2.12 | Versioned experiment tracking, model registry |
| ML Models | PyTorch + PyTorch Geometric | GNN training (SchNet/MACE), CUDA for GPU |
| API | FastAPI | Async I/O, auto-generated OpenAPI docs |
| Frontend | React + Three.js + D3.js + Recharts | 3D molecular viz, dimensionality reduction plots, dashboards |
| Serving | Nginx | Static file serving + reverse proxy |
| Monitoring | Prometheus + Grafana | Metrics scraping across all services |
| Orchestration | Docker Compose | Multi-container orchestration with health checks |

## Two-machine dev setup

The pipeline is designed to run across two machines during development, split by what each machine is good at:

| Service | Alienware R7 (GPU + data) | ROG Ally X (portable) |
|---------|:-------------------------:|:---------------------:|
| PostgreSQL / Redis / MLflow | x | |
| data-ingestion-worker | x | x (connects to R7) |
| ml-training-worker | x (needs 1080 Ti) | |
| prediction-worker | | x (CPU-bound) |
| api / frontend | | x |
| prometheus / grafana | x | |

**R7** runs the GPU workload and data layer. **Ally X** runs everything that doesn't need a GPU.

To use the split setup, copy `.env.example` to `.env` on the Ally X and uncomment the remote override section, pointing `DATABASE_URL`, `REDIS_URL`, and `MLFLOW_TRACKING_URI` at the R7's IP.

```bash
# On the R7:
docker compose up db redis mlflow ml-training-worker data-ingestion-worker prometheus grafana

# On the Ally X:
docker compose up prediction-worker api frontend
```

For **single-machine** development (everything local), just:

```bash
docker compose up
```

## Getting started

```bash
# 1. Clone the repo
git clone <repo-url> && cd catalyst-pipeline

# 2. Create your env file
cp .env.example .env
# Edit .env — fill in passwords and your Materials Project API key

# 3. Start everything
docker compose up --build

# 4. Access the services
#    Frontend:   http://localhost:3000
#    API docs:   http://localhost:8000/docs
#    MLflow UI:  http://localhost:5000
#    Grafana:    http://localhost:3001
```

The database schema is applied automatically on first boot via `db/init.sql`.

## Project structure

```
catalyst-pipeline/
├── docker-compose.yml          # Orchestration (see header for R7/Ally X split)
├── .env.example                # Copy to .env, fill in secrets
│
├── db/
│   └── init.sql                # PostgreSQL schema (runs on first boot)
│
├── frontend/
│   ├── Dockerfile              # Multi-stage: npm build → nginx serve
│   ├── nginx.conf              # Static files + /api/* and /mlflow/* proxy
│   ├── package.json            # React + Three.js + D3.js + Recharts
│   └── src/                    # React application code
│
├── api/
│   ├── Dockerfile              # Python 3.11 + FastAPI + SQLAlchemy
│   └── app/
│       ├── main.py             # FastAPI app, routes, middleware
│       ├── models.py           # SQLAlchemy ORM models
│       ├── routes/
│       │   ├── candidates.py   # GET /candidates, filtering, ranking
│       │   ├── materials.py    # GET /materials, search, detail
│       │   ├── jobs.py         # POST /jobs/train, POST /jobs/predict
│       │   └── mlflow.py       # Proxy MLflow run history
│       └── tasks.py            # Celery task definitions
│
├── workers/
│   ├── ingestion/              # Materials Project + OC20 data fetch
│   ├── ml/                     # GNN training (SchNet/MACE, GPU-enabled)
│   └── prediction/             # Batch inference + Bayesian optimization
│
└── monitoring/
    ├── prometheus.yml           # Scrape targets
    ├── grafana-datasources/     # Auto-provision Prometheus datasource
    └── grafana-dashboards/      # Drop JSON dashboards here
```
