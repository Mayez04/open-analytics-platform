# Troubleshooting Guide

Common issues and fixes for the Open Analytics Platform.

## Quick diagnostics

Run these first:

```bash
docker compose ps                          # Are all services Up?
docker compose logs <service> --tail 50   # Recent errors
docker compose exec postgres pg_isready -U analytics_user -d analytics_warehouse
```

| Symptom | Likely cause | First check |
|---------|--------------|-------------|
| Service won't start | Port conflict, bad `.env` | `docker compose logs <service>` |
| Empty tables after init | Pipeline failed | `docker compose logs airflow` |
| Can't login to UI | Wrong credentials | Compare with `.env` |
| DAG missing | Syntax error or wrong path | `airflow/dags/` + Airflow logs |

---

## Installation and setup

### `.env file not found`

```
[ERROR] .env file not found
```

**Fix:**

```bash
cp .env.example .env
# or
cp config/env/development.env.example .env
```

### Init script fails immediately

**Fix:** Ensure Docker is running and containers are up:

```bash
docker compose up -d
docker compose ps
./scripts/init-platform.sh
```

On Windows, use PowerShell scripts if Bash is unavailable:

```powershell
.\scripts\init-platform.ps1
```

### `docker compose` command not found

Install Docker Desktop (includes Compose v2). Verify:

```bash
docker compose version
```

Use `docker compose` (v2), not the legacy `docker-compose` (v1).

---

## Container issues

### Container keeps restarting or exits

```bash
docker compose logs <service-name>
```

| Service | Common causes |
|---------|---------------|
| **postgres** | Corrupt data dir, disk full, permission errors on `data/postgres/` |
| **airflow** | PostgreSQL not ready, bad Fernet key, pip install failure |
| **superset** | Build failure, DB migration error |
| **minio** | Permission errors on `data/minio/` |

### Permission denied on `data/` or `airflow/logs/`

On Linux:

```bash
sudo chown -R $USER:$USER data/ airflow/logs/
```

On Windows: ensure Docker Desktop has access to the project drive (Settings → Resources → File sharing).

---

## Network and ports

### Port already in use

```
Bind for 0.0.0.0:8081 failed: port is already allocated
```

**Fix:** Change the port in `.env` (not `docker-compose.yml`):

```env
AIRFLOW_WEB_PORT=8082
```

Then restart:

```bash
docker compose down
docker compose up -d
```

### Cannot connect Superset to PostgreSQL

Use `postgres` as the host inside Docker — **not** `localhost`:

```
postgresql://analytics_user:analytics_password@postgres/analytics_warehouse
```

From your host machine (DBeaver, etc.), use `localhost:5432`.

### Docker Desktop not running (Windows)

```
open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified
```

Start Docker Desktop and wait until it shows "Running".

---

## Service-specific issues

### PostgreSQL

**Connection refused:**

```bash
docker compose logs postgres
docker compose exec postgres pg_isready -U analytics_user
```

**Wrong password after `.env` change:** Existing data in `data/postgres/` was initialized with the old password. Either revert the password in `.env` or reset:

```bash
docker compose down -v
rm -rf data/postgres
docker compose up -d
./scripts/init-platform.sh
```

### Airflow

**"Connection refused" or database errors on startup:**

Airflow waits for PostgreSQL health check. If it keeps failing, check postgres logs first.

**DAG not appearing:**

1. File must be in `airflow/dags/` (not the old root `dags/` folder)
2. Check for Python syntax errors: `docker compose logs airflow`
3. Wait 30–60 seconds for scheduler scan
4. Verify dependencies installed: look for pip errors in Airflow startup logs

**DAG run fails — module not found:**

Airflow installs `airflow/requirements.txt` on startup. Restart Airflow:

```bash
docker compose restart airflow
```

**Pipeline fails — MinIO file not found:**

| DAG | Expected filename in bronze bucket |
|-----|-----------------------------------|
| `csv_minio_to_postgres` | `life_expectancy.csv` |
| `json_to_star_schema` | `dhis2_data_values.json` |

Reload: `./scripts/load-demo-data.sh --skip-pipelines`

### Superset

**Takes very long to start (first run):**

Normal — installs dependencies and runs migrations. Wait 2–3 minutes.

**No database connection after init:**

```bash
./scripts/configure-superset.sh
```

**Charts show no data:**

1. Confirm PostgreSQL has data: `SELECT COUNT(*) FROM raw_data;`
2. Confirm Superset connection uses host `postgres`
3. Refresh dataset schema in Superset (Data → dataset → sync)

### MinIO

**Bucket not found:**

```bash
./scripts/load-demo-data.sh --skip-pipelines
```

Or create manually in console at http://localhost:9001.

---

## Pipeline issues

### DHIS2 DAG fails

1. Config at `airflow/dags/config/dhis2_config.json`
2. Credentials in `.env`: `DHIS2_BASE_URL`, `DHIS2_USERNAME`, `DHIS2_PASSWORD`
3. Network access to DHIS2 instance required

### JSON star schema — empty fact table

Check JSON file exists in MinIO and matches expected structure. Re-run:

```bash
./scripts/load-demo-data.sh --pipelines-only
```

---

## Backup and restore

### Backup fails — PostgreSQL not running

```bash
docker compose up -d
./scripts/backup.sh
```

### Restore fails — dump not found

Verify backup structure:

```
backups/platform-.../
├── manifest.json
└── postgres/analytics_warehouse.sql.gz
```

Use correct database name:

```bash
./scripts/restore.sh backups/platform-... --db-name analytics_warehouse
```

### Superset shows old data after restore

```bash
docker compose restart superset
```

---

## Configuration

### Changed `.env` but services use old values

```bash
docker compose down
docker compose up -d
```

### Pilot mode — `CHANGE_ME_*` passwords

Replace all placeholders in `.env` before starting. See [configuration.md](configuration.md).

---

## Full reset

When nothing else works:

```bash
docker compose down -v
rm -rf data/
docker compose up -d
./scripts/init-platform.sh
```

This deletes all stored data and starts fresh.

---

## Getting help

1. Check [installation-guide.md](installation-guide.md) — setup steps
2. Check [operations-guide.md](operations-guide.md) — daily commands
3. Check [repository-structure.md](repository-structure.md) — file locations
4. Inspect logs: `docker compose logs -f <service>`

## Error reference

| Error message | Solution |
|---------------|----------|
| `pg_isready: no response` | Wait for postgres or check `data/postgres/` permissions |
| `ModuleNotFoundError: lib.platform_config` | DAG import path issue — ensure `airflow/dags/lib/` exists |
| `mc: Unable to locate credentials` | MinIO not running or wrong `MINIO_ROOT_*` in `.env` |
| `Fernet key invalid` | Set valid `AIRFLOW_FERNET_KEY` in `.env` |
| `Bind for 0.0.0.0:XXXX failed` | Change port in `.env` |
