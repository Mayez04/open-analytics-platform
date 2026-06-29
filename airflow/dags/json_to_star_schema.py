from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import boto3
import json
import io
import pandas as pd
from sqlalchemy import create_engine, text

from lib.platform_config import get_platform_config

_cfg = get_platform_config()
MINIO_ENDPOINT   = _cfg["minio_endpoint"]
MINIO_ACCESS_KEY = _cfg["minio_access_key"]
MINIO_SECRET_KEY = _cfg["minio_secret_key"]
BUCKET_NAME      = _cfg["minio_bucket"]
PG_CONN          = _cfg["pg_conn"]

FILE_NAME        = "dhis2_data_values.json"


def _s3():
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )


# ---------------------------------------------------------------------------
# Task 1 — Create the full star-schema DDL (idempotent via DROP … CASCADE)
# ---------------------------------------------------------------------------
def create_warehouse_schema():
    engine = create_engine(PG_CONN)
    with engine.begin() as conn:
        conn.execute(text("""
            -- ── Staging (bronze → silver) ──────────────────────────────
            DROP TABLE IF EXISTS stg_data_values CASCADE;
            CREATE TABLE stg_data_values (
                data_element            TEXT,
                period                  TEXT,
                org_unit                TEXT,
                category_option_combo   TEXT,
                attribute_option_combo  TEXT,
                value                   TEXT,
                stored_by               TEXT,
                created_at              TIMESTAMP,
                last_updated_at         TIMESTAMP,
                comment                 TEXT,
                followup                BOOLEAN
            );

            -- ── Dimension tables (gold layer) ───────────────────────────
            DROP TABLE IF EXISTS dim_data_element CASCADE;
            CREATE TABLE dim_data_element (
                data_element_key  SERIAL PRIMARY KEY,
                data_element_code TEXT NOT NULL UNIQUE
            );

            DROP TABLE IF EXISTS dim_period CASCADE;
            CREATE TABLE dim_period (
                period_key  SERIAL PRIMARY KEY,
                period_code TEXT NOT NULL UNIQUE,
                year        INTEGER,
                month       INTEGER
            );

            DROP TABLE IF EXISTS dim_org_unit CASCADE;
            CREATE TABLE dim_org_unit (
                org_unit_key  SERIAL PRIMARY KEY,
                org_unit_code TEXT NOT NULL UNIQUE
            );

            DROP TABLE IF EXISTS dim_category_option_combo CASCADE;
            CREATE TABLE dim_category_option_combo (
                category_option_combo_key  SERIAL PRIMARY KEY,
                category_option_combo_code TEXT NOT NULL UNIQUE
            );

            DROP TABLE IF EXISTS dim_attribute_option_combo CASCADE;
            CREATE TABLE dim_attribute_option_combo (
                attribute_option_combo_key  SERIAL PRIMARY KEY,
                attribute_option_combo_code TEXT NOT NULL UNIQUE
            );

            DROP TABLE IF EXISTS dim_stored_by CASCADE;
            CREATE TABLE dim_stored_by (
                stored_by_key SERIAL PRIMARY KEY,
                username      TEXT NOT NULL UNIQUE
            );

            -- ── Fact table (gold layer) ──────────────────────────────────
            DROP TABLE IF EXISTS fact_data_values CASCADE;
            CREATE TABLE fact_data_values (
                fact_key                   SERIAL PRIMARY KEY,
                data_element_key           INTEGER NOT NULL REFERENCES dim_data_element(data_element_key),
                period_key                 INTEGER NOT NULL REFERENCES dim_period(period_key),
                org_unit_key               INTEGER NOT NULL REFERENCES dim_org_unit(org_unit_key),
                category_option_combo_key  INTEGER NOT NULL REFERENCES dim_category_option_combo(category_option_combo_key),
                attribute_option_combo_key INTEGER NOT NULL REFERENCES dim_attribute_option_combo(attribute_option_combo_key),
                stored_by_key              INTEGER NOT NULL REFERENCES dim_stored_by(stored_by_key),
                value                      NUMERIC,
                created_at                 TIMESTAMP,
                last_updated_at            TIMESTAMP,
                comment                    TEXT,
                followup                   BOOLEAN
            );
        """))
    print("Star-schema DDL applied.")


# ---------------------------------------------------------------------------
# Task 2 — Pull JSON from MinIO and write to the staging table
# ---------------------------------------------------------------------------
def extract_to_staging():
    obj = _s3().get_object(Bucket=BUCKET_NAME, Key=FILE_NAME)
    raw = json.loads(obj["Body"].read())
    records = raw["dataValues"]

    df = pd.DataFrame(records)
    df = df.rename(columns={
        "dataElement":          "data_element",
        "orgUnit":              "org_unit",
        "categoryOptionCombo":  "category_option_combo",
        "attributeOptionCombo": "attribute_option_combo",
        "storedBy":             "stored_by",
        "created":              "created_at",
        "lastUpdated":          "last_updated_at",
    })

    # Parse timestamps — strip timezone so Postgres TIMESTAMP accepts them
    df["created_at"]      = pd.to_datetime(df["created_at"],      utc=True).dt.tz_convert(None)
    df["last_updated_at"] = pd.to_datetime(df["last_updated_at"], utc=True).dt.tz_convert(None)
    df["followup"]        = df["followup"].astype(bool)

    engine = create_engine(PG_CONN)
    df.to_sql("stg_data_values", engine, if_exists="append", index=False)
    print(f"Staged {len(df):,} records into stg_data_values.")


# ---------------------------------------------------------------------------
# Task 3 — Build and load all dimension tables from the staging data
# ---------------------------------------------------------------------------
def load_dimension_tables():
    engine = create_engine(PG_CONN)
    stg = pd.read_sql("SELECT * FROM stg_data_values", engine)

    # dim_data_element
    df = pd.DataFrame({"data_element_code": stg["data_element"].dropna().unique()})
    df.to_sql("dim_data_element", engine, if_exists="append", index=False)
    print(f"dim_data_element: {len(df)} rows")

    # dim_period — also derive year and month from the YYYYMM code
    periods = stg["period"].dropna().unique()
    df = pd.DataFrame({
        "period_code": periods,
        "year":        [int(str(p)[:4]) for p in periods],
        "month":       [int(str(p)[4:6]) for p in periods],
    })
    df.to_sql("dim_period", engine, if_exists="append", index=False)
    print(f"dim_period: {len(df)} rows")

    # dim_org_unit
    df = pd.DataFrame({"org_unit_code": stg["org_unit"].dropna().unique()})
    df.to_sql("dim_org_unit", engine, if_exists="append", index=False)
    print(f"dim_org_unit: {len(df)} rows")

    # dim_category_option_combo
    df = pd.DataFrame({"category_option_combo_code": stg["category_option_combo"].dropna().unique()})
    df.to_sql("dim_category_option_combo", engine, if_exists="append", index=False)
    print(f"dim_category_option_combo: {len(df)} rows")

    # dim_attribute_option_combo
    df = pd.DataFrame({"attribute_option_combo_code": stg["attribute_option_combo"].dropna().unique()})
    df.to_sql("dim_attribute_option_combo", engine, if_exists="append", index=False)
    print(f"dim_attribute_option_combo: {len(df)} rows")

    # dim_stored_by
    df = pd.DataFrame({"username": stg["stored_by"].dropna().unique()})
    df.to_sql("dim_stored_by", engine, if_exists="append", index=False)
    print(f"dim_stored_by: {len(df)} rows")


# ---------------------------------------------------------------------------
# Task 4 — Join staging + dimensions and populate the fact table
# ---------------------------------------------------------------------------
def load_fact_table():
    engine = create_engine(PG_CONN)
    with engine.begin() as conn:
        result = conn.execute(text("""
            INSERT INTO fact_data_values (
                data_element_key,
                period_key,
                org_unit_key,
                category_option_combo_key,
                attribute_option_combo_key,
                stored_by_key,
                value,
                created_at,
                last_updated_at,
                comment,
                followup
            )
            SELECT
                de.data_element_key,
                p.period_key,
                ou.org_unit_key,
                coc.category_option_combo_key,
                aoc.attribute_option_combo_key,
                sb.stored_by_key,
                CAST(NULLIF(TRIM(s.value), '') AS NUMERIC),
                s.created_at,
                s.last_updated_at,
                s.comment,
                s.followup
            FROM stg_data_values            s
            JOIN dim_data_element           de  ON de.data_element_code            = s.data_element
            JOIN dim_period                 p   ON p.period_code                   = s.period
            JOIN dim_org_unit               ou  ON ou.org_unit_code                = s.org_unit
            JOIN dim_category_option_combo  coc ON coc.category_option_combo_code  = s.category_option_combo
            JOIN dim_attribute_option_combo aoc ON aoc.attribute_option_combo_code = s.attribute_option_combo
            JOIN dim_stored_by              sb  ON sb.username                     = s.stored_by
        """))
        print(f"fact_data_values: {result.rowcount:,} rows inserted.")


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="json_lakehouse_to_star_schema",
    description="Extract JSON from MinIO, transform to star schema, load to Postgres",
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,   # trigger manually (or change to a cron expression)
    catchup=False,
    tags=["lakehouse", "star-schema", "etl"],
) as dag:

    t_schema = PythonOperator(
        task_id="create_warehouse_schema",
        python_callable=create_warehouse_schema,
    )

    t_extract = PythonOperator(
        task_id="extract_to_staging",
        python_callable=extract_to_staging,
    )

    t_dims = PythonOperator(
        task_id="load_dimension_tables",
        python_callable=load_dimension_tables,
    )

    t_fact = PythonOperator(
        task_id="load_fact_table",
        python_callable=load_fact_table,
    )

    t_schema >> t_extract >> t_dims >> t_fact
