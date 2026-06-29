# Open Analytics Platform

A self-contained, open-source analytics platform running entirely on your machine via Docker. Combines object storage, a structured warehouse, pipeline orchestration, and business intelligence — with an AI-assisted analytics layer planned for Phase 5.

## Architecture

```
┌──────────┐    ┌───────────┐    ┌──────────┐    ┌───────────┐
│  MinIO   │───▶│ PostgreSQL│◀───│  Airflow │    │ Superset  │
│  (Lake)  │    │(Warehouse)│    │(Orchestr)│    │  (Viz)    │
│ :9000/01 │    │  :5432    │    │  :8081   │    │  :8088    │
└──────────┘    └───────────┘    └──────────┘    └───────────┘
```

| Service | Role |
|---------|------|
| **MinIO** | Raw file storage (CSV, JSON, Parquet) |
| **PostgreSQL** | Structured analytics database |
| **Airflow** | Pipeline scheduling and ETL |
| **Superset** | Charts and dashboards |

## Quick start

**Prerequisites:** Docker and Docker Compose v2.

```bash
git clone <repository-url>
cd open-analytics-platform
cp .env.example .env          # configure credentials and ports
docker compose up -d
./scripts/init-platform.sh    # load demo data and configure services
```

On Windows (PowerShell):

```powershell
Copy-Item .env.example .env
docker compose up -d
.\scripts\init-platform.ps1
```

See the [Configuration Guide](docs/configuration.md) for deployment modes and all available settings.

See the full [Installation Guide](docs/installation-guide.md) for details.

## Service access

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| MinIO Console | http://localhost:9001 | see `.env` | see `.env` |
| Airflow | http://localhost:8081 | see `.env` | see `.env` |
| Superset | http://localhost:8088 | see `.env` | see `.env` |
| PostgreSQL | `localhost:5432` | see `.env` | see `.env` |

Default development credentials are in `.env.example`. Copy to `.env` before starting.

## Project structure

```
open-analytics-platform/
├── docker-compose.yml      # Service definitions
├── docs/                   # Documentation
├── airflow/dags/           # ETL pipeline scripts
├── postgres/sample_data/   # Sample datasets
├── minio/                  # Bucket configuration
├── superset/               # BI config and dashboards
├── assistant/              # AI assistant (Phase 5)
├── scripts/                # Deployment scripts (Phase 4.3)
└── data/                   # Runtime volumes (gitignored)
```

Full details: [docs/repository-structure.md](docs/repository-structure.md)

## Documentation

| Guide | Description |
|-------|-------------|
| [Documentation Index](docs/README.md) | Full documentation map |
| [Platform Overview](docs/platform-overview.md) | Stakeholder presentation |
| [Configuration](docs/configuration.md) | Environment variables and deployment modes |
| [Architecture](docs/architecture.md) | Platform overview and data flow |
| [Installation](docs/installation-guide.md) | Setup instructions |
| [Demo Guide](docs/demo-guide.md) | Client demo walkthrough |
| [Backup & Restore](docs/backup-restore-guide.md) | Backup and recovery procedures |
| [Operations](docs/operations-guide.md) | Day-to-day usage |
| [Troubleshooting](docs/troubleshooting-guide.md) | Common issues |
| [Repository Structure](docs/repository-structure.md) | Folder layout and conventions |

## Pipelines

| DAG | Description |
|-----|-------------|
| `csv_minio_to_postgres` | Load CSV from MinIO into PostgreSQL |
| `json_to_star_schema` | Transform JSON into a star schema |
| `dhis2_to_star_schema` | Extract from DHIS2 API into star schema |

Sample data files are in `postgres/sample_data/`. The init script uploads them to MinIO and runs the matching Airflow DAGs automatically.

```bash
./scripts/load-demo-data.sh    # reload demo data anytime
```

## Common commands

```bash
docker compose up -d              # Start
docker compose down               # Stop (preserves data)
docker compose ps                 # Check status
docker compose logs -f airflow    # Follow logs
./scripts/backup.sh               # Create backup
docker compose down -v && rm -rf data/  # Full reset
```

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| MVP | Core stack (MinIO, PostgreSQL, Airflow, Superset) | Done |
| Phase 4 | Productization (config, scripts, docs, backup) | Done |
| Phase 5 | AI analytics assistant (metadata, NL-to-SQL) | Planned |
| Phase 6 | Security (Keycloak, RBAC, audit) | Planned |
