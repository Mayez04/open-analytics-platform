# Bronze bucket

The `bronze` bucket stores raw, unprocessed files (CSV, JSON, Parquet) before ETL pipelines load them into PostgreSQL.

Sample source files live in `postgres/sample_data/` and are uploaded to MinIO by Airflow DAGs or the demo load script (Phase 4.3).
