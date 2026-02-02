# Catalyst Discovery Pipeline — Study Outline

---

## 1. The Big Picture: What This Pipeline Actually Does

- The core problem: the search space of possible catalyst materials is astronomically large. Traditional lab work tests one material at a time. This pipeline flips that — it screens millions of candidates *in silico* and surfaces the ones most worth testing in a real lab.
- The loop matters more than any single stage. Data comes in, a model learns from it, predictions go out, the best candidates get validated, and validation results become new training data. The pipeline is designed around this cycle, not around any one-off job.
- Key question to keep asking yourself at each stage: *what does this stage need from the one before it, and what does it hand off to the one after?*

---

## 2. The Data Layer: Where Everything Starts

### 2.1 What data exists and where it comes from
- **Materials Project** — the primary source. Hundreds of thousands of inorganic materials with DFT-computed properties (band gap, formation energy, stability, etc.). Has a well-documented API.
- **OC20 (Open Catalyst 2020)** — massive dataset built specifically for catalyst discovery. Bulk download, not API-based.
- **AFLOW** — another materials database, overlapping but not identical coverage.
- These are not perfect. They're biased toward materials that have already been studied. That tension — predicting properties of materials *unlike* anything in your training set — is a core challenge you'll come back to.

### 2.2 Ingestion: getting data into the system
- The ingestion worker's job is narrow: download from external sources, write into Postgres. Nothing else.
- Raw files are cached in S3 (or a local volume in docker-compose) *before* being parsed. If parsing fails, you don't re-download. This also gives you an audit trail.
- Runs on a schedule (Celery beat), not on-demand. Daily refresh from MP is typical.
- Why it's a separate service from everything else: it's I/O-bound (network, disk), not compute-bound. A hanging API call to Materials Project shouldn't block a training job.

### 2.3 The database schema — understand this early
- **materials** — one row per material. The `properties` column is JSONB because different materials have different sets of known properties. The `structure_json` column holds the full crystal structure.
- **predictions** — model output per material. Includes `uncertainty` — this is critical for active learning later.
- **candidates** — the active learning output. Has a status lifecycle: ranked → flagged → in_validation → validated/rejected.
- **validation_results** — experimental or DFT results that feed back as new labeled training data.
- **active_learning_runs** — logs each iteration of the loop.

---

## 3. The ML Layer: Learning from the Data

### 3.1 Why Graph Neural Networks?
- Molecules and crystals are graphs. Atoms are nodes, bonds are edges, spatial relationships carry information.
- A GNN can learn structure → property relationships that are impossible to derive from first principles alone.
- The key property GNNs respect: *equivariance*. Rotating a molecule doesn't change its properties. The model architecture should encode this symmetry, not just hope to learn it from data.

### 3.2 Don't train from scratch
- Pretrained models exist: MACE, SchNet, DimeNet. These have already learned general molecular representations.
- Transfer learning: take a pretrained model, fine-tune it on your specific prediction task (e.g., water-splitting activity). This gets you much further than training from scratch with limited labeled data.
- The model cache volume exists for exactly this reason — pretrained weights are large (hundreds of MB) and you download them once.

### 3.3 Training in practice
- The training worker pulls jobs from a Redis queue (dispatched by the API).
- It trains on the materials + validation_results that are already in Postgres.
- Every run is logged to MLflow: hyperparameters, loss curves, model weights. This is how you compare runs and reproduce results.
- Training is the only stage that genuinely needs a GPU. Everything else in the pipeline is I/O or CPU bound.

### 3.4 What the model actually outputs
- A predicted property value for each material (e.g., predicted catalytic activity).
- An uncertainty estimate — how confident the model is. This is not optional. It's the input to the next stage.

---

## 4. The Prediction & Active Learning Layer: Choosing What to Test

### 4.1 Batch inference
- The prediction worker loads the best model from MLflow and runs inference across the entire candidate pool.
- This is fast enough on CPU for this use case — you're not serving real-time predictions to end users, you're scoring a batch.

### 4.2 Why active learning, not just "pick the top 10"?
- If you only pick materials the model is *confident* are good, you're exploiting what you already know. You'll miss surprises.
- If you only pick materials the model is *uncertain* about, you're exploring blindly. You waste validation budget on things that turn out to be mediocre.
- **Bayesian optimization** balances these two forces. The acquisition score combines exploitation (high predicted value) and exploration (high uncertainty) into a single ranking.
- Common strategies: Expected Improvement, Upper Confidence Bound. The `exploration_weight` parameter in the schema controls this balance.

### 4.3 The candidate lifecycle
- Materials get scored and ranked. A researcher looks at the top candidates in the dashboard.
- They flag promising ones. Someone runs validation (DFT calculation or actual lab synthesis).
- Results come back and get written to `validation_results`.
- Those results become new labeled data. The loop closes.

---

## 5. The Orchestration Layer: How It All Fits Together

### 5.1 Redis as the message broker
- Three separate queues (one per worker type) so jobs don't block each other.
- The API dispatches jobs. Workers pull and execute them asynchronously.
- Celery is the task queue framework. Beat is the scheduler for periodic jobs (like daily ingestion).

### 5.2 MLflow as the experiment registry
- Every training run is versioned. You can compare runs, reproduce them, and load any previous model.
- The "best model" that the prediction worker loads is just whichever MLflow run had the best validation metric.

### 5.3 The API as the single entry point
- The frontend and any external consumers only talk to the API.
- The API doesn't do heavy computation. It serves cached results, dispatches jobs, and proxies MLflow history.
- FastAPI is async — most of its work is waiting on DB queries and Redis, so async matters here.

### 5.4 The network isolation model
- Three Docker networks: frontend, backend, ML.
- The frontend can never reach the database directly. The ML workers can never reach the web UI.
- This isn't just security — it's a clarity of design. Each layer has a defined interface to the next.

---

## 6. The Loop: The Thing That Makes It All Work

This is the single most important thing to internalize:

```
Ingest data → Train model → Predict across candidates →
Active learning selects next batch → Validate selected →
Validation results become new training data → repeat
```

Each iteration of this loop should make the model better. The active learning step is what makes it *efficient* — you're not validating randomly, you're validating the materials most likely to teach the model something new or reveal something valuable.

---

## 7. Questions to Sit With As You Go

- Why is the prediction worker separate from the training worker? (Different resource profiles, different latency requirements.)
- Why cache raw data before parsing? (Resilience, audit trail, re-processability.)
- What happens if the model is wrong about a candidate? (It gets validated, the result feeds back, the next model learns from the mistake.)
- What's the distribution shift problem, and why does it matter here? (You're predicting properties of materials unlike anything in training. This is the hard ML problem underneath all the software.)
- When does this pipeline actually need a GPU, and when doesn't it? (Only training. Everything else is I/O or CPU.)
