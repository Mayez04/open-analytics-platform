# Demo Guide

This guide walks through a client-ready demo of the Open Analytics Platform after running the automated setup.

## Before the demo

```bash
git clone <repository-url>
cd open-analytics-platform
cp .env.example .env
docker compose up -d
./scripts/init-platform.sh
```


Wait until the script prints **Platform initialization complete**.

## Demo flow (15–20 minutes)

### 1. Platform overview (2 min)

Explain the stack:

| Component | Purpose |
|-----------|---------|
| MinIO | Raw data lake (bronze layer) |
| PostgreSQL | Analytics warehouse (gold layer) |
| Airflow | ETL orchestration |
| Superset | Dashboards and exploration |

Open the architecture diagram: [architecture.md](architecture.md)

### 2. Show raw data in MinIO (3 min)

1. Open http://localhost:9001 (credentials from `.env`)
2. Open the **bronze** bucket
3. Show `life_expectancy.csv` and `dhis2_data_values.json`
4. Explain: raw files land here before transformation

### 3. Show ETL in Airflow (5 min)

1. Open http://localhost:8081
2. Navigate to **DAGs**
3. Highlight:
   - `csv_minio_to_postgres` — loads CSV into PostgreSQL
   - `json_to_star_schema` — builds a star schema from JSON
4. Open a successful DAG run (triggered by `init-platform.sh`)
5. Show task logs for the extract/transform/load steps

### 4. Explore data in PostgreSQL (3 min)

Connect with any SQL client or via Docker:

```bash
docker exec -it lakehouse_db psql -U analytics_user -d analytics_warehouse
```

Example queries:

```sql
-- CSV pipeline result
SELECT COUNT(*) FROM raw_data;

-- Star schema pipeline result
SELECT COUNT(*) FROM fact_data_values;
SELECT * FROM dim_org_unit LIMIT 5;
```

### 5. Visualize in Superset (5 min)

1. Open http://localhost:8088
2. Go to **Settings → Database Connections**
3. Confirm **Analytics Warehouse** is configured (added by init script)
4. Create a simple chart:
   - Dataset: `raw_data` or `fact_data_values`
   - Chart type: bar or line
5. Save to a dashboard

> Pre-built dashboard exports will be added to `superset/dashboards/` in a future update.



## Reloading demo data

To reset and reload sample data without restarting containers:

```bash
./scripts/load-demo-data.sh
```

Upload to MinIO only (no pipelines):

```bash
./scripts/load-demo-data.sh --skip-pipelines
```

Run pipelines only (MinIO already has files):

```bash
./scripts/load-demo-data.sh --pipelines-only
```

## Troubleshooting during a demo

| Issue | Fix |
|-------|-----|
| init script fails on MinIO | Check `docker compose ps` — all services must be Up |
| Airflow DAG not found | Wait 1–2 min after startup, then re-run `./scripts/load-demo-data.sh` |
| Empty PostgreSQL tables | Re-run `./scripts/load-demo-data.sh --pipelines-only` |
| Superset has no database | Run `./scripts/configure-superset.sh` |

See [troubleshooting-guide.md](troubleshooting-guide.md) for more.
