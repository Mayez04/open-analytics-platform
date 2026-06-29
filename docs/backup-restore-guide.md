# Backup and Restore Guide

This guide explains how to back up and restore the Open Analytics Platform.

## What gets backed up

| Component | Contents | Location in backup |
|-----------|----------|-------------------|
| **PostgreSQL** | Analytics data + Airflow metadata (same database) | `postgres/{db_name}.sql.gz` |
| **MinIO** | Raw files in the bronze bucket | `minio/{bucket}/` |
| **Superset** | Dashboard and connection metadata (SQLite) | `superset/superset.db` |
| **Configuration** | `.env`, `docker-compose.yml`, DAG configs | `config/` |

Each backup includes a `manifest.json` describing its contents and timestamp.

## Create a backup

Ensure the platform is running:

```bash
docker compose up -d
./scripts/backup.sh
```


Backups are stored in `./backups/platform-YYYYMMDD-HHMMSS/` by default.

### Options

```bash
./scripts/backup.sh --label pre-demo          # custom label in folder name
./scripts/backup.sh --output-dir /path/to/dir # custom backup root
./scripts/backup.sh --archive                 # also create .tar.gz archive
```

## Restore from backup

```bash
./scripts/restore.sh backups/platform-20250614-120000
```


You can restore from a directory or a `.tar.gz` archive.

### Options

| Option | Description |
|--------|-------------|
| `--db-name NAME` | Target PostgreSQL database (default: from manifest or `.env`) |
| `--postgres-only` | Restore PostgreSQL only |
| `--minio-only` | Restore MinIO only |
| `--superset-only` | Restore Superset metadata only |
| `--config-only` | Restore configuration files only |
| `--skip-postgres` | Skip PostgreSQL |
| `--skip-minio` | Skip MinIO |
| `--skip-superset` | Skip Superset |
| `--with-config` | Also restore `.env` and DAG configs |
| `--force` | Skip confirmation prompt |

### Examples

```bash
# Full restore
./scripts/restore.sh backups/platform-20250614-120000

# Restore only the analytics database
./scripts/restore.sh backups/platform-20250614-120000 --postgres-only

# Restore from archive into a specific database name
./scripts/restore.sh backups/platform-20250614-120000.tar.gz --db-name analytics_warehouse

# Restore config without touching data
./scripts/restore.sh backups/platform-20250614-120000 --config-only
```

## Backup folder structure

```
backups/platform-20250614-120000/
├── manifest.json
├── postgres/
│   └── analytics_warehouse.sql.gz
├── minio/
│   └── bronze/
│       ├── life_expectancy.csv
│       └── dhis2_data_values.json
├── superset/
│   └── superset.db
└── config/
    ├── .env
    ├── .env.example
    ├── docker-compose.yml
    └── airflow-dags-config/
        └── dhis2_config.json
```

## Recommended backup schedule

| Environment | Frequency | Retention |
|-------------|-----------|-----------|
| Development | Before major changes | 1–3 latest |
| Pilot / demo | Before each client demo | Last 5 |
| Production | Daily (automated cron) | 30 days |

Example cron (Linux):

```cron
0 2 * * * cd /path/to/open-analytics-platform && ./scripts/backup.sh --archive
```

## Important notes

### PostgreSQL and Airflow share one database

Airflow metadata is stored in the same PostgreSQL database as your analytics tables (`analytics_warehouse` by default). A single dump covers both.

### Superset metadata is container-local

Superset stores its metadata in SQLite inside the container (`/app/superset_home/superset.db`). The backup script extracts this file while Superset is running. After restore, the Superset container is restarted.

### `.env` contains secrets

Backups include your `.env` file in `config/`. Store backups securely and never commit them to Git. The `backups/` folder is gitignored.

### Credential mismatch after restore

If you restore a backup that includes a different `.env` (via `--with-config`), ensure running containers use matching credentials. When in doubt:

```bash
docker compose down
docker compose up -d
./scripts/init-platform.sh --skip-demo   # re-verify services only
```

### Full platform rebuild from backup

1. Clone the repository and copy `.env.example` to `.env`
2. Start containers: `docker compose up -d`
3. Restore: `./scripts/restore.sh backups/platform-... --with-config --force`
4. Restart: `docker compose restart`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `PostgreSQL container is not running` | Run `docker compose up -d` first |
| `manifest.json not found` | Use the backup folder root, not a subfolder |
| Restore fails on PostgreSQL | Check dump file exists at `postgres/{db_name}.sql.gz` |
| Superset shows old data after restore | Run `docker compose restart superset` |
| MinIO bucket empty after restore | Verify `minio/{bucket}/` exists in backup |

See also [troubleshooting-guide.md](troubleshooting-guide.md).
