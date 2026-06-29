# Deployment Scripts

Automated setup and operations for the Open Analytics Platform.

## Quick start (after clone)

```bash
cp .env.example .env
docker compose up -d
./scripts/init-platform.sh
```

On Windows (PowerShell):

```powershell
Copy-Item .env.example .env
docker compose up -d
.\scripts\init-platform.ps1
```

## Scripts

| Script | Purpose |
|--------|---------|
| `init-platform.sh` / `.ps1` | Full platform initialization after `docker compose up -d` |
| `load-demo-data.sh` / `.ps1` | Upload sample data to MinIO and run ETL pipelines |
| `configure-superset.sh` / `.ps1` | Register PostgreSQL connection in Superset |
| `backup.sh` / `.ps1` | Backup databases, MinIO, Superset metadata, and config |
| `restore.sh` / `.ps1` | Restore from backup |

## init-platform

Waits for all services, loads demo data, configures Superset, and prints access URLs.

```bash
./scripts/init-platform.sh              # full init
./scripts/init-platform.sh --skip-demo  # skip demo data load
```

## backup

Creates a timestamped backup in `./backups/`:

```bash
./scripts/backup.sh
./scripts/backup.sh --label pre-demo --archive
```

## restore

```bash
./scripts/restore.sh backups/platform-20250614-120000
./scripts/restore.sh backups/platform-20250614-120000 --postgres-only
./scripts/restore.sh backups/platform-20250614-120000 --with-config --force
```

## load-demo-data

Uploads files from `postgres/sample_data/` to the MinIO bronze bucket and runs Airflow pipelines.

```bash
./scripts/load-demo-data.sh                    # upload + run pipelines
./scripts/load-demo-data.sh --skip-pipelines   # upload to MinIO only
./scripts/load-demo-data.sh --pipelines-only   # run pipelines only
```

## What gets initialized

1. Runtime directories (`data/minio`, `data/postgres`, `airflow/logs`)
2. MinIO **bronze** bucket with sample CSV and JSON files
3. PostgreSQL tables via Airflow DAGs (`raw_data`, star schema)
4. Superset **Analytics Warehouse** database connection

See [docs/backup-restore-guide.md](../docs/backup-restore-guide.md) for backup and restore procedures.

Keycloak and demo dashboards will be added in later phases.

See [docs/demo-guide.md](../docs/demo-guide.md) for a client demo walkthrough.
