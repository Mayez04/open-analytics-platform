# Repository Structure

This document describes the layout of the **Open Analytics Platform** repository  and is part of the complete documentation set .

## Top-level layout

```
open-analytics-platform/
├── docker-compose.yml      # Service definitions (reads from .env)
├── .env.example            # Configuration template
├── .env                    # Local config (gitignored)
├── config/env/             # Deployment presets (development, pilot)
├── README.md
├── .gitignore
│
├── docs/                   # Platform documentation
├── airflow/                # Pipeline orchestration
├── postgres/               # Database init, migrations, sample data
├── minio/                  # Object storage bucket and policy definitions
├── superset/               # BI configuration and dashboards
├── assistant/              # AI analytics assistant (Phase 5)
├── scripts/                # Deployment and operations scripts (Phase 4.3)
├── tests/                  # Automated tests
└── data/                   # Runtime Docker volumes (gitignored)
```

## Directory reference

### `docs/`

| File | Purpose |
|------|---------|
| `architecture.md` | High-level platform architecture |
| `configuration.md` | Environment variables and deployment modes |
| `backup-restore-guide.md` | Backup and recovery procedures |
| `platform-overview.md` | Stakeholder presentation (Phase 4.5) |
| `repository-structure.md` | This file |
| `installation-guide.md` | Step-by-step installation |
| `operations-guide.md` | Day-to-day operations |
| `troubleshooting-guide.md` | Common issues and fixes |

### `airflow/`

| Path | Purpose |
|------|---------|
| `dags/` | Airflow DAG definitions (ETL pipelines) |
| `dags/config/` | External JSON/YAML config for DAGs (e.g. DHIS2 credentials) |
| `plugins/` | Custom Airflow plugins |
| `logs/` | Runtime scheduler and task logs (gitignored) |
| `requirements.txt` | Python dependencies used by DAGs |

**Naming convention for DAGs:** `{source}_to_{target}.py` (e.g. `csv_to_postgres.py`, `json_to_star_schema.py`).

### `postgres/`

| Path | Purpose |
|------|---------|
| `init/` | SQL scripts run on first container start (`/docker-entrypoint-initdb.d`) |
| `migrations/` | Versioned schema changes |
| `sample_data/` | Source datasets for demos and pipeline testing |

### `minio/`

| Path | Purpose |
|------|---------|
| `buckets/` | Bucket documentation and configuration |
| `policies/` | Access policies (future) |

Runtime object storage data lives in `data/minio/` (gitignored).

### `superset/`

| Path | Purpose |
|------|---------|
| `Dockerfile` | Custom Superset image (adds PostgreSQL driver) |
| `config/` | Superset configuration overrides |
| `dashboards/` | Exported dashboard definitions |

### `assistant/` (Phase 5)

| Path | Purpose |
|------|---------|
| `backend/` | FastAPI service (NL-to-SQL, validation, audit) |
| `frontend/` | Streamlit UI |
| `metadata/` | YAML/JSON metadata describing analytical databases |

### `scripts/` (Phase 4.3)

| Script | Purpose |
|--------|---------|
| `init-platform.sh` / `.ps1` | One-shot platform initialization |
| `load-demo-data.sh` / `.ps1` | Load sample datasets |
| `configure-superset.sh` / `.ps1` | Register PostgreSQL in Superset |
| `backup.sh` / `.ps1` | Backup databases, MinIO, Superset, and config |
| `restore.sh` / `.ps1` | Restore from backup |

### `data/` (gitignored)

Docker volume mount points. Created locally at runtime — never committed.

| Path | Purpose |
|------|---------|
| `data/minio/` | MinIO object storage |
| `data/postgres/` | PostgreSQL data directory |

## Naming conventions

| Area | Convention | Example |
|------|------------|---------|
| DAG files | `snake_case`, verb describing flow | `csv_to_postgres.py` |
| DAG IDs | `snake_case`, matches purpose | `csv_minio_to_postgres` |
| Config files | `{system}_config.json` | `dhis2_config.json` |
| Environment | `.env` (local), `.env.example` (template) | `.env.example` |
| Sample data | `snake_case`, descriptive | `life_expectancy.csv` |
| Documentation | `kebab-case.md` | `installation-guide.md` |

## What goes where

| Content type | Location |
|--------------|----------|
| Infrastructure (Docker) | Root `docker-compose.yml` |
| ETL pipelines | `airflow/dags/` |
| Pipeline configuration | `airflow/dags/config/` |
| Database schema / seed SQL | `postgres/init/`, `postgres/migrations/` |
| Raw sample files | `postgres/sample_data/` |
| BI assets | `superset/dashboards/` |
| AI assistant code | `assistant/` |
| Ops automation | `scripts/` |
| Runtime state | `data/` (local only) |

## Current pipelines

| DAG | File | Description |
|-----|------|-------------|
| `csv_minio_to_postgres` | `airflow/dags/csv_to_postgres.py` | Load CSV from MinIO bronze bucket into PostgreSQL |
| `json_to_star_schema` | `airflow/dags/json_to_star_schema.py` | Transform DHIS2-style JSON into a star schema |
| `dhis2_to_star_schema` | `airflow/dags/dhis2_to_star_schema.py` | Extract from DHIS2 API → MinIO → star schema |

## Adding a new component

1. Create a top-level folder with a clear name (`assistant/`, not `ai-stuff/`).
2. Add a `README.md` inside if the folder is not self-explanatory.
3. Update this document and `docs/architecture.md`.
4. Wire the service into `docker-compose.yml` when ready.
