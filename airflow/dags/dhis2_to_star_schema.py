from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import boto3
import json
import os
import requests
import pandas as pd
from sqlalchemy import create_engine, text

from lib.platform_config import get_platform_config

# ---------------------------------------------------------------------------
# Load pipeline-specific config (datasets, dates, schedule)
# Credentials come from environment variables via .env
# ---------------------------------------------------------------------------
_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config", "dhis2_config.json")

with open(_CONFIG_PATH) as _f:
    _CFG = json.load(_f)

_platform = get_platform_config()

# DHIS2 — credentials from environment variables (.env)
DHIS2_BASE_URL = os.environ["DHIS2_BASE_URL"]
DHIS2_AUTH = (os.environ["DHIS2_USERNAME"], os.environ["DHIS2_PASSWORD"])

# Extraction
DATASETS       = _CFG["extraction"]["datasets"]
ROOT_ORG_UNIT  = _CFG["extraction"]["root_org_unit"]
START_DATE     = _CFG["extraction"]["start_date"]
END_DATE       = _CFG["extraction"]["end_date"]

# Schedule
_SCHEDULE_START = datetime.strptime(_CFG["schedule"]["start_date"], "%Y-%m-%d")
_SCHEDULE_FREQ  = _CFG["schedule"]["frequency"]

# MinIO and PostgreSQL — from platform environment
MINIO_ENDPOINT   = _platform["minio_endpoint"]
MINIO_ACCESS_KEY = _platform["minio_access_key"]
MINIO_SECRET_KEY = _platform["minio_secret_key"]
BUCKET_NAME      = _platform["minio_bucket"]
PG_CONN          = _platform["pg_conn"]

# Derived
DATASET_IDS    = [ds["uid"] for ds in DATASETS]
RAW_OBJECT_KEY = f"dhis2/dataValues_{START_DATE}_{END_DATE}.json"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _s3():
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )


def _dhis2_get(path, params=None):
    r = requests.get(
        f"{DHIS2_BASE_URL}/api/{path}",
        auth=DHIS2_AUTH,
        params=params or {},
        timeout=180,
    )
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------------
# Task 1 — Fetch dataValueSets from DHIS2 → raw JSON in MinIO (bronze)
#           Supports multiple datasets: merges all dataValues into one file
# ---------------------------------------------------------------------------
def land_raw_to_minio():
    all_values = []
    for ds_uid in DATASET_IDS:
        data = _dhis2_get("dataValueSets.json", {
            "dataSet":   ds_uid,
            "orgUnit":   ROOT_ORG_UNIT,
            "children":  "true",
            "startDate": START_DATE,
            "endDate":   END_DATE,
        })
        records = data.get("dataValues", [])
        # Tag each record with its source dataset
        for r in records:
            r["sourceDataSet"] = ds_uid
        all_values.extend(records)
        print(f"  Dataset {ds_uid}: {len(records):,} records fetched")

    payload = {"dataValues": all_values}
    _s3().put_object(
        Bucket=BUCKET_NAME,
        Key=RAW_OBJECT_KEY,
        Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )
    print(f"Total {len(all_values):,} records stored → s3://{BUCKET_NAME}/{RAW_OBJECT_KEY}")


# ---------------------------------------------------------------------------
# Task 2 — Discover OU hierarchy depth and create the full star-schema DDL
# ---------------------------------------------------------------------------
def create_warehouse_schema(**context):
    data = _dhis2_get("organisationUnits.json", {
        "paging": "false",
        "filter": f"path:like:{ROOT_ORG_UNIT}",
        "fields": "level",
    })
    max_level = max(ou["level"] for ou in data["organisationUnits"])
    context["ti"].xcom_push(key="max_level", value=max_level)
    print(f"Hierarchy depth: {max_level} levels")

    level_cols = "\n".join(
        f"    ou_level{lvl}_uid  TEXT,\n"
        f"    ou_level{lvl}_code TEXT,\n"
        f"    ou_level{lvl}_name TEXT,"
        for lvl in range(1, max_level + 1)
    )

    engine = create_engine(PG_CONN)
    with engine.begin() as conn:
        conn.execute(text(f"""
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
                followup                BOOLEAN,
                source_data_set         TEXT
            );

            DROP TABLE IF EXISTS dim_org_unit CASCADE;
            CREATE TABLE dim_org_unit (
                org_unit_key SERIAL PRIMARY KEY,
                {level_cols}
                ou_uid  TEXT UNIQUE NOT NULL,
                ou_code TEXT,
                ou_name TEXT
            );

            DROP TABLE IF EXISTS dim_data_element CASCADE;
            CREATE TABLE dim_data_element (
                data_element_key  SERIAL PRIMARY KEY,
                data_element_uid  TEXT NOT NULL UNIQUE,
                data_element_code TEXT,
                data_element_name TEXT
            );

            DROP TABLE IF EXISTS dim_period CASCADE;
            CREATE TABLE dim_period (
                period_key  SERIAL PRIMARY KEY,
                period_code TEXT NOT NULL UNIQUE,
                year        INTEGER,
                month       INTEGER
            );

            DROP TABLE IF EXISTS dim_category_option_combo CASCADE;
            CREATE TABLE dim_category_option_combo (
                category_option_combo_key  SERIAL PRIMARY KEY,
                category_option_combo_uid  TEXT NOT NULL UNIQUE,
                category_option_combo_code TEXT,
                category_option_combo_name TEXT
            );

            DROP TABLE IF EXISTS dim_attribute_option_combo CASCADE;
            CREATE TABLE dim_attribute_option_combo (
                attribute_option_combo_key  SERIAL PRIMARY KEY,
                attribute_option_combo_uid  TEXT NOT NULL UNIQUE,
                attribute_option_combo_code TEXT,
                attribute_option_combo_name TEXT
            );

            DROP TABLE IF EXISTS dim_stored_by CASCADE;
            CREATE TABLE dim_stored_by (
                stored_by_key SERIAL PRIMARY KEY,
                username      TEXT NOT NULL UNIQUE
            );

            DROP TABLE IF EXISTS fact_data_values CASCADE;
            CREATE TABLE fact_data_values (
                
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
                followup                   BOOLEAN,
                source_data_set            TEXT
            );
        """))
    print(f"Schema created — {max_level} OU hierarchy levels.")


# ---------------------------------------------------------------------------
# Task 3 — Read raw JSON from MinIO → staging table
# ---------------------------------------------------------------------------
def extract_data_values():
    obj = _s3().get_object(Bucket=BUCKET_NAME, Key=RAW_OBJECT_KEY)
    data = json.loads(obj["Body"].read())
    records = data.get("dataValues", [])

    df = pd.DataFrame(records)
    df = df.rename(columns={
        "dataElement":          "data_element",
        "orgUnit":              "org_unit",
        "categoryOptionCombo":  "category_option_combo",
        "attributeOptionCombo": "attribute_option_combo",
        "storedBy":             "stored_by",
        "created":              "created_at",
        "lastUpdated":          "last_updated_at",
        "sourceDataSet":        "source_data_set",
    })
    df["created_at"]      = pd.to_datetime(df["created_at"],      utc=True).dt.tz_convert(None)
    df["last_updated_at"] = pd.to_datetime(df["last_updated_at"], utc=True).dt.tz_convert(None)
    df["followup"]        = df["followup"].astype(bool)

    engine = create_engine(PG_CONN)
    df.to_sql("stg_data_values", engine, if_exists="append", index=False)
    print(f"Staged {len(df):,} dataValues records.")


# ---------------------------------------------------------------------------
# Task 4 — Build dim_org_unit with full dynamic hierarchy
# ---------------------------------------------------------------------------
def load_dim_org_unit(**context):
    max_level = context["ti"].xcom_pull(task_ids="create_warehouse_schema", key="max_level")

    data = _dhis2_get("organisationUnits.json", {
        "paging":  "false",
        "filter":  f"path:like:{ROOT_ORG_UNIT}",
        "fields":  "id,code,displayName,level,path",
    })
    ous = data["organisationUnits"]

    uid_info = {
        ou["id"]: {"code": ou.get("code", ""), "name": ou["displayName"]}
        for ou in ous
    }

    rows = []
    for ou in ous:
        path_uids = [u for u in ou["path"].split("/") if u]
        row = {}
        for pos, uid in enumerate(path_uids):
            lvl = pos + 1
            info = uid_info.get(uid, {})
            row[f"ou_level{lvl}_uid"]  = uid
            row[f"ou_level{lvl}_code"] = info.get("code", "")
            row[f"ou_level{lvl}_name"] = info.get("name", "")
        row["ou_uid"]  = ou["id"]
        row["ou_code"] = ou.get("code", "")
        row["ou_name"] = ou["displayName"]
        rows.append(row)

    pd.DataFrame(rows).to_sql("dim_org_unit", create_engine(PG_CONN), if_exists="append", index=False)
    print(f"dim_org_unit: {len(rows):,} rows ({max_level} levels)")


# ---------------------------------------------------------------------------
# Task 5 — Build dim_data_element
# ---------------------------------------------------------------------------
def load_dim_data_element():
    engine = create_engine(PG_CONN)
    uids = pd.read_sql(
        "SELECT DISTINCT data_element FROM stg_data_values", engine
    )["data_element"].tolist()

    data = _dhis2_get("dataElements.json", {
        "paging":  "false",
        "fields":  "id,code,displayName",
        "filter":  f"id:in:[{','.join(uids)}]",
    })
    rows = [
        {
            "data_element_uid":  de["id"],
            "data_element_code": de.get("code", ""),
            "data_element_name": de["displayName"],
        }
        for de in data["dataElements"]
    ]
    pd.DataFrame(rows).to_sql("dim_data_element", engine, if_exists="append", index=False)
    print(f"dim_data_element: {len(rows)} rows")


# ---------------------------------------------------------------------------
# Task 6 — Build remaining dimensions
# ---------------------------------------------------------------------------
def load_other_dimensions():
    engine = create_engine(PG_CONN)
    stg = pd.read_sql("SELECT * FROM stg_data_values", engine)

    # dim_category_option_combo
    coc_uids = stg["category_option_combo"].dropna().unique().tolist()
    data = _dhis2_get("categoryOptionCombos.json", {
        "paging": "false", "fields": "id,code,displayName",
        "filter": f"id:in:[{','.join(coc_uids)}]",
    })
    pd.DataFrame([
        {"category_option_combo_uid": c["id"], "category_option_combo_code": c.get("code", ""),
         "category_option_combo_name": c["displayName"]}
        for c in data["categoryOptionCombos"]
    ]).to_sql("dim_category_option_combo", engine, if_exists="append", index=False)
    print(f"dim_category_option_combo: {len(data['categoryOptionCombos'])} rows")

    # dim_attribute_option_combo
    aoc_uids = stg["attribute_option_combo"].dropna().unique().tolist()
    data = _dhis2_get("categoryOptionCombos.json", {
        "paging": "false", "fields": "id,code,displayName",
        "filter": f"id:in:[{','.join(aoc_uids)}]",
    })
    pd.DataFrame([
        {"attribute_option_combo_uid": c["id"], "attribute_option_combo_code": c.get("code", ""),
         "attribute_option_combo_name": c["displayName"]}
        for c in data["categoryOptionCombos"]
    ]).to_sql("dim_attribute_option_combo", engine, if_exists="append", index=False)
    print(f"dim_attribute_option_combo: {len(data['categoryOptionCombos'])} rows")

    # dim_period
    periods = stg["period"].dropna().unique()
    pd.DataFrame({
        "period_code": periods,
        "year":        [int(str(p)[:4]) for p in periods],
        "month":       [int(str(p)[4:6]) for p in periods],
    }).to_sql("dim_period", engine, if_exists="append", index=False)
    print(f"dim_period: {len(periods)} rows")

    # dim_stored_by
    users = stg["stored_by"].dropna().unique()
    pd.DataFrame({"username": users}).to_sql("dim_stored_by", engine, if_exists="append", index=False)
    print(f"dim_stored_by: {len(users)} rows")


# ---------------------------------------------------------------------------
# Task 7 — Populate fact_data_values
# ---------------------------------------------------------------------------
def load_fact_table():
    engine = create_engine(PG_CONN)
    with engine.begin() as conn:
        result = conn.execute(text("""
            INSERT INTO fact_data_values (
                data_element_key, period_key, org_unit_key,
                category_option_combo_key, attribute_option_combo_key,
                stored_by_key, value, created_at, last_updated_at,
                comment, followup, source_data_set
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
                s.followup,
                s.source_data_set
            FROM stg_data_values            s
            JOIN dim_data_element           de  ON de.data_element_uid            = s.data_element
            JOIN dim_period                 p   ON p.period_code                  = s.period
            JOIN dim_org_unit               ou  ON ou.ou_uid                      = s.org_unit
            JOIN dim_category_option_combo  coc ON coc.category_option_combo_uid  = s.category_option_combo
            JOIN dim_attribute_option_combo aoc ON aoc.attribute_option_combo_uid = s.attribute_option_combo
            JOIN dim_stored_by              sb  ON sb.username                    = s.stored_by
        """))
        print(f"fact_data_values: {result.rowcount:,} rows inserted.")


# ---------------------------------------------------------------------------
# Task 8 — Create analytics views over dimensions and fact
# ---------------------------------------------------------------------------
def create_analytics_views(**context):
    max_level = context["ti"].xcom_pull(task_ids="create_warehouse_schema", key="max_level")
    ou_level_cols = ",\n                ".join(
        f"ou.ou_level{lvl}_uid,\n                ou.ou_level{lvl}_code,\n                ou.ou_level{lvl}_name"
        for lvl in range(1, max_level + 1)
    )

    engine = create_engine(PG_CONN)
    with engine.begin() as conn:
        conn.execute(text("""
            CREATE OR REPLACE VIEW vw_dim_org_unit AS
            SELECT * FROM dim_org_unit;

            CREATE OR REPLACE VIEW vw_dim_data_element AS
            SELECT * FROM dim_data_element;
        """))
        conn.execute(text(f"""
            CREATE OR REPLACE VIEW vw_fact_data_values AS
            SELECT
                f.data_element_key,
                f.period_key,
                f.org_unit_key,
                f.category_option_combo_key,
                f.attribute_option_combo_key,
                f.stored_by_key,
                f.value,
                f.created_at,
                f.last_updated_at,
                f.comment,
                f.followup,
                f.source_data_set,
                de.data_element_uid,
                de.data_element_code,
                de.data_element_name,
                ou.ou_uid,
                ou.ou_code,
                ou.ou_name,
                {ou_level_cols}
            FROM fact_data_values  f
            JOIN dim_data_element  de ON de.data_element_key = f.data_element_key
            JOIN dim_org_unit      ou ON ou.org_unit_key       = f.org_unit_key;
        """))
    print("Analytics views created: vw_dim_org_unit, vw_dim_data_element, vw_fact_data_values.")


# ---------------------------------------------------------------------------
# DAG definition — schedule driven entirely by config file
# ---------------------------------------------------------------------------
with DAG(
    dag_id="dhis2_to_star_schema",
    description="Land raw DHIS2 API JSON in MinIO → star schema in Postgres",
    start_date=_SCHEDULE_START,
    schedule_interval=_SCHEDULE_FREQ,
    catchup=False,
    tags=["dhis2", "star-schema", "etl", "minio", "bronze"],
) as dag:

    t0 = PythonOperator(task_id="land_raw_to_minio",        python_callable=land_raw_to_minio)
    t1 = PythonOperator(task_id="create_warehouse_schema",  python_callable=create_warehouse_schema, provide_context=True)
    t2 = PythonOperator(task_id="extract_data_values",      python_callable=extract_data_values)
    t3 = PythonOperator(task_id="load_dim_org_unit",        python_callable=load_dim_org_unit, provide_context=True)
    t4 = PythonOperator(task_id="load_dim_data_element",    python_callable=load_dim_data_element)
    t5 = PythonOperator(task_id="load_other_dimensions",    python_callable=load_other_dimensions)
    t6 = PythonOperator(task_id="load_fact_table",          python_callable=load_fact_table)
    t7 = PythonOperator(task_id="create_analytics_views",   python_callable=create_analytics_views, provide_context=True)

    t0 >> t1 >> t2 >> [t3, t4, t5] >> t6 >> t7