# Operations Guide

Day-to-day operations for running the Open Analytics Platform in development or pilot environments.

## Service management

### Start and stop

```bash
docker compose up -d              # Start all services (background)
docker compose down               # Stop (data preserved)
docker compose restart airflow    # Restart a single service
docker compose ps                 # Check status
```

### Container names

| Service | Container name |
|---------|----------------|
| MinIO | `lakehouse_minio` |
| PostgreSQL | `lakehouse_db` |
| Airflow | `lakehouse_airflow` |
| Superset | `lakehouse_superset` |

### First-time vs subsequent starts

| Scenario | Command |
|----------|---------|
| First install | `docker compose up -d` then `./scripts/init-platform.sh` |
| Daily restart | `docker compose up -d` |
| After config change | `docker compose down && docker compose up -d` |
| After `.env` password change | Full reset or restore from backup |

## Health checks

Verify all services are healthy before a demo or backup:

```bash
docker compose ps
```

| Service | Health check |
|---------|--------------|
| PostgreSQL | `docker compose exec postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` |
| MinIO | Open http://localhost:9001 or `curl http://localhost:9000/minio/health/live` |
| Airflow | Open http://localhost:8081/health |
| Superset | Open http://localhost:8088/login/ |

Automated check via init script:

```bash
./scripts/init-platform.sh --skip-demo   # verifies services without reloading data
```

## Viewing logs

```bash
docker compose logs                    # All services (last snapshot)
docker compose logs -f airflow         # Follow Airflow logs live
docker compose logs -f superset        # Follow Superset logs
docker compose logs -f postgres        # Follow PostgreSQL logs
docker compose logs -f minio           # Follow MinIO logs
docker compose logs airflow --tail 100 # Last 100 lines
```

Useful log patterns to look for:

| Service | Ready signal |
|---------|--------------|
| Airflow | `Listening at: http://0.0.0.0:8080` |
| Superset | `Running on http://0.0.0.0:8088` |
| PostgreSQL | `database system is ready to accept connections` |

## Running pipelines

### Via Airflow UI

1. Open http://localhost:8081 (credentials from `.env`)
2. Enable the DAG toggle
3. Click the **play** button → **Trigger DAG**

### Via CLI

```bash
docker compose exec airflow airflow dags list
docker compose exec airflow airflow dags test csv_minio_to_postgres 2024-01-01
```

### Available DAGs

| DAG ID | Input | Output |
|--------|-------|--------|
| `csv_minio_to_postgres` | `life_expectancy.csv` in MinIO bronze | `raw_data` table |
| `json_to_star_schema` | `dhis2_data_values.json` in MinIO bronze | Star schema tables |
| `dhis2_to_star_schema` | DHIS2 API (live extraction) | MinIO + star schema |

Reload all demo pipelines:

```bash
./scripts/load-demo-data.sh
```

## Managing data

### MinIO (raw files)

- **Console:** http://localhost:9001
- **Default bucket:** `bronze` (configurable via `MINIO_BUCKET` in `.env`)
- Upload files via console or: `./scripts/load-demo-data.sh --skip-pipelines`

### PostgreSQL (structured data)

Connect from the host using values from `.env`:

```
Host:     localhost
Port:     ${POSTGRES_PORT}
Database: ${POSTGRES_DB}
User:     ${POSTGRES_USER}
Password: ${POSTGRES_PASSWORD}
```

Connect from inside Docker:

```bash
docker exec -it lakehouse_db psql -U analytics_user -d analytics_warehouse
```

Useful inspection queries:

```sql
\dt                          -- list tables
SELECT COUNT(*) FROM raw_data;
SELECT COUNT(*) FROM fact_data_values;
```

### Superset

- **URL:** http://localhost:8088
- Database connection **Analytics Warehouse** is created by `init-platform.sh`
- Re-create manually: `./scripts/configure-superset.sh`

## Adding a new pipeline

1. Create `airflow/dags/{source}_to_{target}.py`
2. Use `lib/platform_config.py` for connection settings (never hardcode credentials)
3. Put external config in `airflow/dags/config/`
4. Wait ~30 seconds for Airflow to detect the new DAG
5. Test: `docker compose exec airflow airflow dags test <dag_id> 2024-01-01`

## Configuration changes

After editing `.env`:

```bash
docker compose down
docker compose up -d
```

Port-only changes take effect on restart. Password changes for PostgreSQL require either keeping the existing `data/postgres/` volume or a full reset.

See [configuration.md](configuration.md) for all variables.

## Backup and restore

### Before a demo or upgrade

```bash
./scripts/backup.sh --label pre-demo
./scripts/backup.sh --archive          # also create .tar.gz
```

### Restore

```bash
./scripts/restore.sh backups/platform-YYYYMMDD-HHMMSS
./scripts/restore.sh backups/platform-....tar.gz --force
```

Component-level restore:

```bash
./scripts/restore.sh backups/platform-... --postgres-only
./scripts/restore.sh backups/platform-... --minio-only
```

Full documentation: [backup-restore-guide.md](backup-restore-guide.md).

## Maintenance tasks

### Reload demo data

```bash
./scripts/load-demo-data.sh
```

### Re-configure Superset connection

```bash
./scripts/configure-superset.sh
```

### Clear Airflow logs

```bash
rm -rf airflow/logs/*
```

### Full platform reset

Deletes all data — use before a clean demo or when credentials change:

```bash
docker compose down -v
rm -rf data/
docker compose up -d
./scripts/init-platform.sh
```

### Update Docker images

```bash
docker compose pull
docker compose up -d --build
```

## Resource usage

Typical local deployment:

| Resource | Approximate |
|----------|-------------|
| Disk (images) | ~3 GB |
| Disk (runtime data) | 500 MB – 2 GB |
| RAM | 4–8 GB recommended |
| CPU | 2+ cores |

First startup takes 2–5 minutes (image pull + DB migrations + pip install in Airflow).

## Deployment modes

| Mode | Preset | Use case |
|------|--------|----------|
| Development | `config/env/development.env.example` | Local work |
| Pilot | `config/env/pilot.env.example` | Client demos |

Set via `DEPLOYMENT_MODE` in `.env`. See [configuration.md](configuration.md).

## Operational checklist

### Daily

- [ ] `docker compose ps` — all services Up
- [ ] Airflow UI accessible
- [ ] Superset UI accessible

### Before a client demo

- [ ] `./scripts/backup.sh --label pre-demo`
- [ ] `./scripts/load-demo-data.sh` — fresh demo data
- [ ] Verify Superset database connection
- [ ] Review [demo-guide.md](demo-guide.md)

### After a demo

- [ ] Optional: restore from pre-demo backup if data was modified
- [ ] Review Airflow logs for failed DAG runs

## Related documentation

- [Installation Guide](installation-guide.md)
- [Configuration Guide](configuration.md)
- [Backup and Restore Guide](backup-restore-guide.md)
- [Troubleshooting Guide](troubleshooting-guide.md)
