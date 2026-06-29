# Installation Guide

## Prerequisites

### Software

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | 24+ | [Docker Desktop](https://www.docker.com/products/docker-desktop/) for Windows/Mac |
| Docker Compose | v2 | Bundled with Docker Desktop; use `docker compose` not `docker-compose` |
| Git | any recent | To clone the repository |

### Hardware (recommended)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 4 GB | 8 GB |
| Disk | 10 GB free | 20 GB free |
| CPU | 2 cores | 4 cores |

### Optional

- **Bash** (Git Bash or WSL) for `.sh` scripts on Windows
- **PowerShell 5.1+** for `.ps1` scripts on Windows
- SQL client (DBeaver, pgAdmin) for PostgreSQL inspection

Verify:

```bash
docker --version
docker compose version
```

## Quick install

### 1. Clone the repository

```bash
git clone <repository-url>
cd open-analytics-platform
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` to set credentials and ports, or use a preset:

```bash
cp config/env/development.env.example .env   # local development
cp config/env/pilot.env.example .env         # client demo
```

See [Configuration Guide](configuration.md) for all variables.

### 3. Start the platform

```bash
docker compose up -d
```

The first run downloads images (~2–3 GB) and initializes Airflow and Superset databases (1–2 minutes).

### 4. Initialize the platform

```bash
./scripts/init-platform.sh
```




This script:

- Waits for all services to be ready
- Creates the MinIO **bronze** bucket and uploads sample data
- Runs demo ETL pipelines in Airflow
- Registers the PostgreSQL connection in Superset

Optional-Skip demo data loading:

```bash
./scripts/init-platform.sh --skip-demo
```

Runtime directories (`data/`, `airflow/logs/`) are created automatically.

### 5. Verify services

```bash
docker compose ps
```

All four services should show `Up` or `running`.

Wait for Airflow and Superset to finish initializing:

```bash
docker compose logs -f airflow
# Look for: "Listening at: http://0.0.0.0:8080"

docker compose logs -f superset
# Look for: "Running on http://0.0.0.0:8088"
```

### Verification checklist

- [ ] All four containers show `Up` in `docker compose ps`
- [ ] MinIO console loads at http://localhost:9001
- [ ] Airflow UI loads at http://localhost:8081
- [ ] Superset UI loads at http://localhost:8088
- [ ] `init-platform.sh` completed without errors
- [ ] MinIO bronze bucket contains sample files
- [ ] PostgreSQL has data: `SELECT COUNT(*) FROM raw_data;`
- [ ] Superset shows **Analytics Warehouse** database connection

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| MinIO Console | http://localhost:9001 | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` from `.env` |
| Airflow | http://localhost:8081 | `AIRFLOW_ADMIN_USER` / `AIRFLOW_ADMIN_PASSWORD` from `.env` |
| Superset | http://localhost:8088 | `SUPERSET_ADMIN_USER` / `SUPERSET_ADMIN_PASSWORD` from `.env` |
| PostgreSQL | `localhost:5432` | `POSTGRES_USER` / `POSTGRES_PASSWORD` from `.env` |

> Development defaults are in `.env.example`. Never commit your `.env` file.

## Connect Superset to PostgreSQL

1. Open http://localhost:8088
2. Go to **Settings → Database Connections → + Database**
3. Choose **PostgreSQL**
4. Enter the connection string using values from your `.env`:

```
postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres/${POSTGRES_DB}
```

Use `postgres` as the host (Docker service name, not `localhost`).

## Load sample data

Sample files live in `postgres/sample_data/`:

- `life_expectancy.csv`
- `dhis2_data_values.json`

The init script handles upload and pipeline execution automatically. To reload later:

```bash
./scripts/load-demo-data.sh
```

Options:

```bash
./scripts/load-demo-data.sh --skip-pipelines   # upload to MinIO only
./scripts/load-demo-data.sh --pipelines-only   # run DAGs only
```

See [Demo Guide](demo-guide.md) for a full walkthrough.

## Stopping and resetting

```bash
# Stop (preserves data)
docker compose down

# Full reset (deletes all data)
docker compose down -v
rm -rf data/
```

## Next steps

- [Demo Guide](demo-guide.md) — client demo walkthrough
- [Backup and Restore Guide](backup-restore-guide.md) — backup and recovery
- [Operations Guide](operations-guide.md) — day-to-day usage
- [Troubleshooting Guide](troubleshooting-guide.md) — common issues
- [Repository Structure](repository-structure.md) — folder layout
