-- =============================================================================
-- Schema for the catalyst discovery pipeline
-- =============================================================================
-- This runs once, on first container boot, via Docker's
-- /docker-entrypoint-initdb.d/ mechanism. It will NOT re-run on subsequent
-- starts. If you need to migrate the schema later, use a proper migration
-- tool (Alembic with SQLAlchemy is the standard choice for this stack).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- materials
-- ---------------------------------------------------------------------------
-- Core table. One row per material in the database. The `properties` JSONB
-- column stores whatever DFT-computed properties came with the material from
-- the source dataset — band gap, formation energy, density, etc. This is
-- intentionally schema-less for that column because different materials have
-- different sets of known properties, and the Materials Project adds new
-- computed properties over time.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS materials (
    id              SERIAL PRIMARY KEY,
    source          VARCHAR(50) NOT NULL,           -- 'materials_project', 'oc20', 'aflow', etc.
    source_id       VARCHAR(255) NOT NULL,          -- The ID in the original database (e.g., 'mp-1234')
    formula         VARCHAR(255) NOT NULL,          -- Chemical formula as a string
    crystal_system  VARCHAR(50),                    -- cubic, tetragonal, etc.
    space_group     INTEGER,
    num_atoms       INTEGER,
    properties      JSONB DEFAULT '{}',             -- All computed properties from source
    structure_json  JSONB,                          -- Full crystal structure (sites, lattice, etc.)
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),

    UNIQUE (source, source_id)                      -- No duplicates from the same source
);

CREATE INDEX idx_materials_formula ON materials (formula);
CREATE INDEX idx_materials_source ON materials (source);
CREATE INDEX idx_materials_properties ON materials USING GIN (properties);

-- ---------------------------------------------------------------------------
-- predictions
-- ---------------------------------------------------------------------------
-- Model output for each material. Stores the predicted property value,
-- the confidence/uncertainty estimate (critical for active learning), and
-- which model run produced it. One material can have many predictions over
-- time as models improve.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS predictions (
    id              SERIAL PRIMARY KEY,
    material_id     INTEGER NOT NULL REFERENCES materials(id),
    model_run_id    VARCHAR(255) NOT NULL,          -- MLflow run ID
    target_property VARCHAR(100) NOT NULL,          -- e.g., 'water_splitting_activity', 'co2_reduction_potential'
    predicted_value FLOAT NOT NULL,
    uncertainty     FLOAT,                          -- Std dev from ensemble or MC dropout
    confidence      FLOAT,                          -- 0-1 confidence score
    created_at      TIMESTAMP DEFAULT NOW(),

    UNIQUE (material_id, model_run_id, target_property)
);

CREATE INDEX idx_predictions_material ON predictions (material_id);
CREATE INDEX idx_predictions_run ON predictions (model_run_id);
CREATE INDEX idx_predictions_target ON predictions (target_property);

-- ---------------------------------------------------------------------------
-- candidates
-- ---------------------------------------------------------------------------
-- The active learning output layer. After predictions are generated, the
-- Bayesian optimization loop scores each material as a candidate for
-- experimental validation. This table stores that ranking.
--
-- status tracks the lifecycle:
--   'ranked'        -> just scored by active learning
--   'flagged'       -> a researcher has flagged it for validation
--   'in_validation' -> someone is actually running experiments on it
--   'validated'     -> results are back
--   'rejected'      -> didn't pan out
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidates (
    id                  SERIAL PRIMARY KEY,
    material_id         INTEGER NOT NULL REFERENCES materials(id),
    prediction_id       INTEGER NOT NULL REFERENCES predictions(id),
    acquisition_score   FLOAT NOT NULL,             -- Bayesian optimization score (higher = more interesting)
    exploration_weight  FLOAT,                      -- How much of the score came from uncertainty (vs. predicted value)
    exploitation_weight FLOAT,                      -- How much came from raw predicted performance
    rank                INTEGER,                    -- Position in the ranked list at time of scoring
    status              VARCHAR(50) DEFAULT 'ranked',
    notes               TEXT,                       -- Researcher notes
    flagged_by          VARCHAR(255),               -- Who flagged it
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_candidates_material ON candidates (material_id);
CREATE INDEX idx_candidates_status ON candidates (status);
CREATE INDEX idx_candidates_score ON candidates (acquisition_score DESC);

-- ---------------------------------------------------------------------------
-- validation_results
-- ---------------------------------------------------------------------------
-- When a candidate actually gets validated experimentally (or via a more
-- expensive DFT calculation), the results go here. This feeds back into
-- the training loop — these become new labeled data points for the next
-- model training run.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS validation_results (
    id                  SERIAL PRIMARY KEY,
    candidate_id        INTEGER NOT NULL REFERENCES candidates(id),
    material_id         INTEGER NOT NULL REFERENCES materials(id),
    validation_method   VARCHAR(100) NOT NULL,      -- 'dft', 'experimental', 'semi_empirical'
    target_property     VARCHAR(100) NOT NULL,
    measured_value      FLOAT NOT NULL,
    measurement_error   FLOAT,
    validated_by        VARCHAR(255),
    notes               TEXT,
    created_at          TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_validation_candidate ON validation_results (candidate_id);
CREATE INDEX idx_validation_material ON validation_results (material_id);

-- ---------------------------------------------------------------------------
-- active_learning_runs
-- ---------------------------------------------------------------------------
-- Logs each active learning iteration. Useful for understanding how the
-- system's recommendations evolve over time and whether the exploration/
-- exploitation balance is well-tuned.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS active_learning_runs (
    id                      SERIAL PRIMARY KEY,
    run_timestamp           TIMESTAMP DEFAULT NOW(),
    model_run_id            VARCHAR(255) NOT NULL,  -- Which model's predictions were used
    num_candidates_scored   INTEGER NOT NULL,
    num_candidates_selected INTEGER NOT NULL,       -- How many were flagged this round
    exploration_weight      FLOAT,                  -- The alpha parameter used
    strategy                VARCHAR(100),           -- e.g., 'expected_improvement', 'upper_confidence_bound'
    notes                   TEXT
);
